import XCTest
@testable import UsageCore

final class SessionsTests: XCTestCase {
    /// The shape `claude agents --json` printed on 2026-10-24 (two of ten entries).
    static let agents = """
    [
      {"id": "d05a75de", "cwd": "/Users/u/ai-coding/agents-workdocs", "kind": "background",
       "startedAt": 1790406769886, "sessionId": "d05a75de-c561", "name": "Broken symlinks", "state": "blocked"},
      {"pid": 43708, "cwd": "/Users/u/aiwork/tools/tiler", "kind": "interactive",
       "startedAt": 1792809140956, "sessionId": "f01c5ec5-61e8", "name": "tiler", "status": "busy"},
      {"pid": 7989, "cwd": "/Users/u/officework", "kind": "interactive",
       "startedAt": 1792641374813, "sessionId": "01456043", "status": "idle"}
    ]
    """

    func testDecodeAndSort() throws {
        let list = AgentSession.sorted(try AgentSession.decodeList(Data(Self.agents.utf8)))
        XCTAssertEqual(list.map(\.title), ["Broken symlinks", "tiler", "officework"])   // needs you, working, idle
        XCTAssertTrue(list[0].isBackground)
        XCTAssertEqual(list[0].activity, "blocked")
        XCTAssertEqual(list[1].pid, 43708)
        XCTAssertEqual(list[2].attention, .idle)
    }

    func testShortPath() {
        XCTAssertEqual(AgentSession.shortPath("/Users/u/aiwork/tiler", home: "/Users/u"), "~/aiwork/tiler")
        XCTAssertEqual(AgentSession.shortPath("/Users/u", home: "/Users/u"), "~")
        XCTAssertEqual(AgentSession.shortPath("/Users/uu/x", home: "/Users/u"), "/Users/uu/x")
    }

    func testCmuxTree() {
        let json = """
        {"caller": null, "windows": [
          {"ref": "window:1", "id": "6D78-UUID", "workspaces": [
            {"ref": "workspace:5", "title": "tiler", "panes": [
              {"ref": "pane:5", "surfaces": [
                {"ref": "surface:5", "title": "tiler", "tty": "ttys007", "type": "terminal"},
                {"ref": "surface:6", "title": "web", "tty": null, "type": "browser"}]}]}]}]}
        """
        let s = CmuxSurface.parseTree(Data(json.utf8))
        XCTAssertEqual(s, [CmuxSurface(windowRef: "window:1", windowID: "6D78-UUID", workspaceRef: "workspace:5", surfaceRef: "surface:5",
                                       tty: "ttys007", title: "tiler")])
        XCTAssertEqual(CmuxSurface.parseTree(Data("nonsense".utf8)), [])
    }

    func testTTYNames() {
        XCTAssertEqual(CmuxSurface.normalize("/dev/ttys003"), "ttys003")
        XCTAssertEqual(CmuxSurface.normalize("ttys003"), "ttys003")
        XCTAssertEqual(CmuxSurface.normalize("s003"), "ttys003")
    }

    func testTmux() {
        let panes = TmuxPane.parsePanes("/dev/ttys003\tagent-0b2235\t0\t0\n/dev/ttys011\tagent-65a66c\t0\t0\nbad line\n")
        XCTAssertEqual(panes, [TmuxPane(tty: "ttys003", session: "agent-0b2235", window: "0", pane: "0"),
                               TmuxPane(tty: "ttys011", session: "agent-65a66c", window: "0", pane: "0")])
        XCTAssertEqual(TmuxPane.parseClients("/dev/ttys009\tagent-0b2235\n"), ["agent-0b2235": "ttys009"])
    }

    func testShellQuote() {
        XCTAssertEqual(shellQuote("it's"), #"'it'\''s'"#)
    }
}
