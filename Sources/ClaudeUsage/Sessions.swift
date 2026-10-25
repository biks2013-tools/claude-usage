import AppKit
import UsageCore

/// Run a command line tool and capture its output (stdout only), with a time
/// limit. Call off the main thread.
enum Shell {
    struct Output { let status: Int32; let text: String }

    static func run(_ executable: String, _ arguments: [String], cwd: String? = nil, timeout: TimeInterval = 5) -> Output? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        // A GUI app has no shell PATH; give child tools the usual places.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Tools.searchPath + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["CMUX_QUIET"] = "1"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = DispatchTime.now() + timeout
        let done = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async { data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: deadline) == .timedOut { p.terminate(); return nil }
        p.waitUntilExit()
        return Output(status: p.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }
}

/// Where the tools this app drives live. Found by looking in their usual
/// install places; a missing tool is reported, never guessed.
enum Tools {
    static let home = NSHomeDirectory()
    static let searchPath = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].joined(separator: ":")

    static var claude: String? {
        first(["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"])
    }
    static var tmux: String? { first(["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]) }
    static let cmuxBundleID = "com.cmuxterm.app"
    static var cmux: String? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cmuxBundleID) else { return nil }
        return first([app.appendingPathComponent("Contents/Resources/bin/cmux").path])
    }

    private static func first(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// The open Claude Code sessions, from `claude agents --json`. Asked only when
/// the menu opens, like the usage.
final class SessionsClient {
    private let queue = DispatchQueue(label: "claude-usage.sessions")

    enum Failure: Error {
        case noClaude, failed

        var text: String {
            switch self {
            case .noClaude: return "Claude Code not found (looked in ~/.local/bin, /opt/homebrew/bin, /usr/local/bin)"
            case .failed: return "claude agents --json did not answer"
            }
        }
    }

    func fetch(_ completion: @escaping (Result<[AgentSession], Failure>) -> Void) {
        queue.async {
            let result: Result<[AgentSession], Failure>
            if let claude = Tools.claude {
                if let out = Shell.run(claude, ["agents", "--json"], cwd: Tools.home), out.status == 0,
                   let list = try? AgentSession.decodeList(Data(out.text.utf8)) {
                    result = .success(AgentSession.sorted(list))
                } else {
                    result = .failure(.failed)
                }
            } else {
                result = .failure(.noClaude)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// Takes you to a session:
/// - in a cmux terminal: that window, workspace and tab come forward;
/// - in a tmux pane: tmux selects it, then the terminal attached to that tmux
///   session comes forward; with none attached, a new cmux workspace attaches;
/// - a background session: a new cmux workspace runs `claude attach <id>`;
/// - any other terminal: its app comes forward.
final class Navigator {
    private let queue = DispatchQueue(label: "claude-usage.navigate")

    func go(to session: AgentSession, failed: @escaping (String) -> Void, done: @escaping () -> Void = {}) {
        queue.async {
            let problem = self.navigate(session)
            DispatchQueue.main.async { if let problem { failed(problem) } else { done() } }
        }
    }

    /// Nil on success, else what went wrong.
    private func navigate(_ s: AgentSession) -> String? {
        guard let pid = s.pid else {
            guard let claude = Tools.claude else { return "Claude Code not found." }
            return openInCmux(name: s.title, cwd: s.cwd, command: "\(shellQuote(claude)) attach \(shellQuote(s.id ?? s.sessionId))")
        }
        guard let tty = ttyOf(pid) else { return "The session has ended." }
        let surfaces = cmuxSurfaces()
        if let surface = surfaces.first(where: { $0.tty == tty }) { return focus(surface) }
        if let (socket, pane) = tmuxPane(tty: tty), let tmux = Tools.tmux {
            _ = Shell.run(tmux, ["-S", socket, "select-window", "-t", "\(pane.session):\(pane.window)"])
            _ = Shell.run(tmux, ["-S", socket, "select-pane", "-t", "\(pane.session):\(pane.window).\(pane.pane)"])
            let clients = TmuxPane.parseClients(Shell.run(tmux, ["-S", socket, "list-clients", "-F", TmuxPane.clientFormat])?.text ?? "")
            if let clientTTY = clients[pane.session] {
                if let surface = surfaces.first(where: { $0.tty == clientTTY }) { return focus(surface) }
                if let clientPID = pidOnTTY(clientTTY) { return activateTerminal(of: clientPID) }
            }
            return openInCmux(name: s.title, cwd: s.cwd,
                              command: "\(shellQuote(tmux)) -S \(shellQuote(socket)) attach -t \(shellQuote(pane.session))")
        }
        return activateTerminal(of: pid)
    }

    // MARK: cmux

    private func cmuxSurfaces() -> [CmuxSurface] {
        guard let cmux = Tools.cmux, let out = Shell.run(cmux, ["tree", "--all", "--json", "--id-format", "both"]),
              out.status == 0 else { return [] }
        return CmuxSurface.parseTree(Data(out.text.utf8))
    }

    /// Select the tab in cmux, show the desktop its window is on, bring cmux forward.
    private func focus(_ s: CmuxSurface) -> String? {
        guard let cmux = Tools.cmux else { return "cmux not found." }
        _ = Shell.run(cmux, ["focus-window", "--window", s.windowRef])
        _ = Shell.run(cmux, ["select-workspace", "--workspace", s.workspaceRef, "--window", s.windowRef])
        let ok = Shell.run(cmux, ["focus-panel", "--panel", s.surfaceRef, "--workspace", s.workspaceRef, "--window", s.windowRef])?.status == 0
        // macOS does not follow an app to a window on another desktop: go there first.
        var problem: String?
        if let uuid = s.windowID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: Tools.cmuxBundleID).first {
            problem = DesktopSwitcher.reveal(pid: app.processIdentifier, axIdentifier: "cmux.main.\(uuid)")
        }
        activate(bundleID: Tools.cmuxBundleID)
        // Now that the window is on screen, make it cmux's front window.
        _ = Shell.run(cmux, ["focus-window", "--window", s.windowRef])
        return problem ?? (ok ? nil : "cmux did not switch to that tab.")
    }

    private func openInCmux(name: String, cwd: String, command: String) -> String? {
        guard let cmux = Tools.cmux else { return "This session has no terminal window, and cmux (used to open one) is not installed." }
        let out = Shell.run(cmux, ["new-workspace", "--name", name, "--cwd", cwd, "--command", command, "--focus", "true"])
        activate(bundleID: Tools.cmuxBundleID)
        return out?.status == 0 ? nil : "cmux could not open a workspace for it."
    }

    // MARK: tmux

    /// The tmux pane (and its server's socket) whose terminal is `tty`.
    private func tmuxPane(tty: String) -> (String, TmuxPane)? {
        guard let tmux = Tools.tmux else { return nil }
        let dir = (ProcessInfo.processInfo.environment["TMUX_TMPDIR"] ?? "/private/tmp") + "/tmux-\(getuid())"
        let sockets = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for name in sockets {
            let socket = dir + "/" + name
            guard let out = Shell.run(tmux, ["-S", socket, "list-panes", "-a", "-F", TmuxPane.paneFormat], timeout: 2),
                  out.status == 0 else { continue }
            if let pane = TmuxPane.parsePanes(out.text).first(where: { $0.tty == tty }) { return (socket, pane) }
        }
        return nil
    }

    // MARK: Processes

    private func ttyOf(_ pid: Int32) -> String? {
        guard let out = Shell.run("/bin/ps", ["-o", "tty=", "-p", "\(pid)"]), out.status == 0 else { return nil }
        let t = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "??" ? nil : CmuxSurface.normalize(t)
    }

    private func pidOnTTY(_ tty: String) -> Int32? {
        guard let out = Shell.run("/bin/ps", ["-t", tty, "-o", "pid="]) else { return nil }
        return out.text.split(separator: "\n").first.flatMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Bring forward the app that owns the process's terminal (the nearest
    /// ancestor that is a regular app).
    private func activateTerminal(of pid: Int32) -> String? {
        var current = pid
        for _ in 0..<32 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                DispatchQueue.main.async { app.activate() }
                return nil
            }
            guard let out = Shell.run("/bin/ps", ["-o", "ppid=", "-p", "\(current)"]),
                  let parent = Int32(out.text.trimmingCharacters(in: .whitespacesAndNewlines)), parent > 1 else { break }
            current = parent
        }
        return "Could not find the terminal window of this session."
    }

    /// Bring an app forward. NSWorkspace works from a background app (this one,
    /// once its menu has closed), where NSRunningApplication.activate may not.
    private func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 2)
    }
}
