import Foundation
import Testing
@testable import TidewatchCore

struct SessionStateTests {
    private let now = Date(timeIntervalSince1970: 1_791_620_000)

    @Test func roundTripsThroughTheStateFileFormat() throws {
        var state = SessionState(sessionId: "s-1", cwd: "/Users/demo/app", host: .vscode, terminalApp: nil, pid: 4242, now: now)
        state.status = .needsApproval
        state.tool = "Bash"
        state.detail = "npm install"
        state.backgroundTasks = 2
        state.lastEvent = now.addingTimeInterval(30)
        let data = try SessionCoding.encoder().encode(state)
        let decoded = try SessionCoding.decoder().decode(SessionState.self, from: data)
        #expect(decoded == state)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"statusSince\" : \"2026-"))
        #expect(text.contains("\"cwd\" : \"/Users/demo/app\""))
    }

    @Test func newSessionStartsIdle() {
        let state = SessionState(sessionId: "s-1", cwd: "/Users/demo/app", host: .terminal, terminalApp: "iTerm.app", pid: nil, now: now)
        #expect(state.status == .idle)
        #expect(state.firstSeen == now)
        #expect(state.statusSince == now)
        #expect(state.lastEvent == now)
        #expect(state.backgroundTasks == 0)
        #expect(state.schema == SessionState.currentSchema)
    }

    @Test func projectIsTheFolderNameEvenWithSpaces() {
        let state = SessionState(sessionId: "s", cwd: "/Users/demo/anna wisniewska", host: .vscode, terminalApp: nil, pid: nil, now: now)
        #expect(state.project == "anna wisniewska")
        #expect(state.id == "s")
    }

    @Test func decodingIgnoresUnknownFields() throws {
        var state = SessionState(sessionId: "s", cwd: "/Users/demo/app", host: .vscode, terminalApp: nil, pid: nil, now: now)
        state.title = "Fix login"
        var object = try JSONSerialization.jsonObject(with: SessionCoding.encoder().encode(state)) as! [String: Any]
        object["futureField"] = ["x": 1]
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try SessionCoding.decoder().decode(SessionState.self, from: data) == state)
    }
}
