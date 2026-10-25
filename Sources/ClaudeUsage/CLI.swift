import AppKit
import UsageCore

/// `claude-usage` in a terminal: the same checks as the menu, printed.
///
///   claude-usage [usage] [--json]   plan limits, the week by product, extra usage
///   claude-usage sessions [--json]  open Claude Code sessions
///   claude-usage go <n|name|id>     go to a session (number from `sessions`)
///   claude-usage help | --version
enum CLI {
    /// The menu bar app is started by Launch Services (parent launchd, pid 1,
    /// no arguments); anything else, from a terminal, a pipe or a script, is
    /// the command.
    static var wanted: Bool {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
        return !args.isEmpty || getppid() != 1
    }

    static func run() -> Never {
        var args = Array(CommandLine.arguments.dropFirst())
        let json = args.contains("--json")
        args.removeAll { $0 == "--json" }
        switch args.first ?? "usage" {
        case "usage": usage(json: json)
        case "sessions", "ls": sessions(json: json)
        case "go", "open":
            guard args.count >= 2 else { fail("usage: claude-usage go <number|name|session id>", code: 2) }
            go(args[1...].joined(separator: " "))
        case "help", "-h", "--help": print(help); exit(0)
        case "--version", "version":
            print("claude-usage \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
            exit(0)
        default: fail("unknown command \"\(args[0])\"\n\n\(help)", code: 2)
        }
    }

    static let help = """
    claude-usage: your Claude subscription's usage and your Claude Code sessions

      claude-usage [usage] [--json]   plan limits with reset times, the week by product, extra usage
      claude-usage sessions [--json]  open Claude Code sessions on this Mac
      claude-usage go <n|name|id>     go to a session (n = its number in `claude-usage sessions`)
      claude-usage --version

    Usage comes from Anthropic with Claude Code's sign-in (read from the Keychain, never stored).
    """

    // MARK: Commands

    private static func usage(json: Bool) -> Never {
        UsageClient().fetch { result in
            switch result {
            case .failure(let e): fail("\(e.title). \(e.detail)")
            case .success(let r):
                if json { FileHandle.standardOutput.write(r.raw); print(); exit(0) }
                printUsage(r)
                exit(0)
            }
        }
        dispatchMain()
    }

    private static func printUsage(_ r: UsageClient.Result) {
        let now = Date()
        print(bold("Claude \(r.plan)".replacingOccurrences(of: "Claude Claude", with: "Claude")))
        let width = r.report.limits.map { Format.title(of: $0).count }.max() ?? 0
        for l in r.report.limits {
            let pct = Format.percent(l.percent).leftPad(4)
            let reset = l.resetsAt.map { "  " + dim(Format.reset($0, now: now)) } ?? ""
            print("  \(Format.title(of: l).rightPad(width))  \(colour(pct, Format.level(of: l)))  \(bar(l.percent))\(reset)")
        }
        if let rows = r.report.weekBreakdown?.rows, !rows.isEmpty {
            print(bold("This week by product"))
            let w = rows.map(\.displayName.count).max() ?? 0
            for row in rows { print("  \(row.displayName.rightPad(w))  \(Format.percent(row.percent).leftPad(4))") }
        }
        var beyond: [String] = []
        if let e = r.report.extraUsage { beyond.append("Extra usage: \(Format.extraUsage(e))") }
        if let used = r.report.spend?.used { beyond.append("Credits spent: \(Format.money(used))") }
        if !beyond.isEmpty { print(dim(beyond.joined(separator: " · "))) }
    }

    private static func sessions(json: Bool) -> Never {
        SessionsClient().fetch { result in
            switch result {
            case .failure(let f): fail(f.text)
            case .success(let list):
                if json {
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    FileHandle.standardOutput.write(try! enc.encode(list)); print(); exit(0)
                }
                if list.isEmpty { print("No Claude Code sessions open."); exit(0) }
                let w = min(list.map(\.title.count).max() ?? 0, 40)
                for (i, s) in list.enumerated() {
                    let state = colour(s.activity.rightPad(7), s.attention == .needsYou ? .warning : s.attention == .working ? .normal : nil)
                    let place = s.isBackground ? "background" : AgentSession.shortPath(s.cwd)
                    print("\(String(i + 1).leftPad(3))  \(state)  \(String(s.title.prefix(40)).rightPad(w))  \(dim(place))")
                }
                exit(0)
            }
        }
        dispatchMain()
    }

    private static func go(_ target: String) -> Never {
        SessionsClient().fetch { result in
            guard case .success(let list) = result else {
                if case .failure(let f) = result { fail(f.text) }
                exit(1)
            }
            let lower = target.lowercased()
            let match: AgentSession? = Int(target).flatMap { list.indices.contains($0 - 1) ? list[$0 - 1] : nil }
                ?? list.first { $0.title.lowercased() == lower }
                ?? list.first { $0.sessionId.hasPrefix(lower) || ($0.id ?? "").hasPrefix(lower) }
                ?? list.first { $0.title.lowercased().contains(lower) }
            guard let s = match else { fail("No session matches \"\(target)\". See: claude-usage sessions") }
            Navigator().go(to: s, failed: { problem in fail(problem) }, done: { exit(0) })
        }
        dispatchMain()
    }

    // MARK: Output

    private static let tty = isatty(STDOUT_FILENO) == 1

    private static func bold(_ s: String) -> String { tty ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
    private static func dim(_ s: String) -> String { tty ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
    private static func colour(_ s: String, _ level: Format.Level?) -> String {
        guard tty, let level else { return s }
        let code = switch level { case .normal: "32"; case .warning: "33"; case .critical: "31" }
        return "\u{1B}[\(code)m\(s)\u{1B}[0m"
    }

    private static func bar(_ percent: Double, width: Int = 20) -> String {
        let filled = Int((min(max(percent, 0), 100) / 100 * Double(width)).rounded())
        return String(repeating: "█", count: filled) + dim(String(repeating: "░", count: width - filled))
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("claude-usage: \(message)\n".utf8))
        exit(code)
    }
}

private extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
    func rightPad(_ n: Int) -> String { count >= n ? self : self + String(repeating: " ", count: n - count) }
}
