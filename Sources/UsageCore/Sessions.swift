import Foundation

/// One open Claude Code session, as `claude agents --json` prints it
/// (documented: "Print active sessions (interactive and background) as a JSON
/// array"). Interactive sessions run in a terminal and carry a `pid`;
/// background ones are managed by Claude Code and are opened with
/// `claude attach <id>`.
public struct AgentSession: Codable, Equatable {
    public let id: String?
    public let pid: Int32?
    public let cwd: String
    public let kind: String
    public let startedAt: Double?
    public let sessionId: String
    public let name: String?
    /// Interactive sessions report `status` (idle, busy, ...), background ones `state` (blocked, ...).
    public let status: String?
    public let state: String?

    public init(id: String?, pid: Int32?, cwd: String, kind: String, startedAt: Double?, sessionId: String,
                name: String?, status: String?, state: String?) {
        self.id = id; self.pid = pid; self.cwd = cwd; self.kind = kind; self.startedAt = startedAt
        self.sessionId = sessionId; self.name = name; self.status = status; self.state = state
    }

    public var isBackground: Bool { pid == nil }

    /// What the session is doing, in one word.
    public var activity: String { status ?? state ?? "unknown" }

    public enum Attention: Int, Comparable {
        case needsYou = 0, working = 1, idle = 2
        public static func < (a: Attention, b: Attention) -> Bool { a.rawValue < b.rawValue }
    }

    /// Blocked or waiting sessions first: they need you.
    public var attention: Attention {
        switch activity {
        case "busy", "running", "working": return .working
        case "idle", "done", "completed": return .idle
        default: return .needsYou   // blocked, waiting, needs input, anything new
        }
    }

    public var title: String {
        if let name, !name.isEmpty { return name }
        return (cwd as NSString).lastPathComponent
    }

    /// Needs-you first, then working, then idle; newest first within each.
    public static func sorted(_ list: [AgentSession]) -> [AgentSession] {
        list.sorted { a, b in
            a.attention != b.attention ? a.attention < b.attention : (a.startedAt ?? 0) > (b.startedAt ?? 0)
        }
    }

    public static func decodeList(_ data: Data) throws -> [AgentSession] {
        try JSONDecoder().decode([AgentSession].self, from: data)
    }

    /// "~/aiwork/tools/tiler" for a folder under `home`.
    public static func shortPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// A terminal surface in cmux, from `cmux tree --all --json`.
public struct CmuxSurface: Equatable {
    public let windowRef: String
    /// The window's UUID (with `--id-format both`); its AX identifier is "cmux.main.<UUID>".
    public let windowID: String?
    public let workspaceRef: String
    public let surfaceRef: String
    public let tty: String
    public let title: String?

    /// Every terminal surface with its tty ("ttys007"). Unknown shapes give an empty list.
    public static func parseTree(_ data: Data) -> [CmuxSurface] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let windows = root["windows"] as? [[String: Any]] else { return [] }
        var result: [CmuxSurface] = []
        for w in windows {
            guard let wref = w["ref"] as? String else { continue }
            let wid = w["id"] as? String
            for ws in w["workspaces"] as? [[String: Any]] ?? [] {
                guard let wsref = ws["ref"] as? String else { continue }
                for pane in ws["panes"] as? [[String: Any]] ?? [] {
                    for s in pane["surfaces"] as? [[String: Any]] ?? [] {
                        guard let sref = s["ref"] as? String, let tty = s["tty"] as? String, !tty.isEmpty else { continue }
                        result.append(CmuxSurface(windowRef: wref, windowID: wid, workspaceRef: wsref, surfaceRef: sref,
                                                  tty: Self.normalize(tty), title: s["title"] as? String))
                    }
                }
            }
        }
        return result
    }

    /// "ttys007" from "/dev/ttys007", "s007" (ps) or "ttys007".
    public static func normalize(_ tty: String) -> String {
        var t = tty.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("/dev/") { t.removeFirst(5) }
        if !t.hasPrefix("tty"), t.hasPrefix("s"), t.dropFirst().allSatisfy(\.isNumber) { t = "tty" + t }
        return t
    }
}

/// A pane of a tmux server, and the clients attached to its sessions.
public struct TmuxPane: Equatable {
    public let tty: String
    public let session: String
    public let window: String
    public let pane: String

    public static let paneFormat = "#{pane_tty}\t#{session_name}\t#{window_index}\t#{pane_index}"
    public static let clientFormat = "#{client_tty}\t#{session_name}"

    public static func parsePanes(_ text: String) -> [TmuxPane] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4 else { return nil }
            return TmuxPane(tty: CmuxSurface.normalize(f[0]), session: f[1], window: f[2], pane: f[3])
        }
    }

    /// session name → the tty of a client attached to it.
    public static func parseClients(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if f.count == 2, result[f[1]] == nil { result[f[1]] = CmuxSurface.normalize(f[0]) }
        }
        return result
    }
}

/// Quote for /bin/sh: 'it'\''s'.
public func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
