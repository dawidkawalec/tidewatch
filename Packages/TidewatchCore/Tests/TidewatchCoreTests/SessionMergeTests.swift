import Foundation
import Testing
@testable import TidewatchCore

/// The hook files carry the detail (which tool waits for approval); Claude Code's registry knows
/// every open session and its project folder. Together they are the list of sessions.
struct SessionMergeTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func process(_ pid: Int32, _ id: String, cwd: String = "/Users/demo/app", status: String? = "idle", kind: String? = "interactive", entrypoint: String? = "claude-vscode", started: TimeInterval = 0) -> ClaudeProcess {
        ClaudeProcess(pid: pid, sessionId: id, cwd: cwd, kind: kind, entrypoint: entrypoint, status: status, waitingFor: nil, startedAt: t0.addingTimeInterval(started), updatedAt: t0.addingTimeInterval(started + 5), statusUpdatedAt: t0.addingTimeInterval(started + 5))
    }

    private func hook(_ id: String, pid: Int32?, cwd: String = "/Users/demo/app", status: SessionStatus = .working, firstSeen: TimeInterval = 100) -> SessionState {
        var state = SessionState(sessionId: id, cwd: cwd, host: .vscode, terminalApp: nil, pid: pid, now: t0.addingTimeInterval(firstSeen))
        state.startedConversation = true
        state.status = status
        return state
    }

    @Test func aHookSessionTakesItsFolderAndStartFromTheRegistry() throws {
        var drifted = hook("s-1", pid: 10, cwd: "/Users/demo/other-repo", status: .needsApproval)
        drifted.tool = "Bash"
        let merged = SessionMerge.merge(hooks: [drifted], processes: [process(10, "s-1", cwd: "/Users/demo/app", status: "busy")])
        let state = try #require(merged.first)
        #expect(merged.count == 1)
        #expect(state.folder == "/Users/demo/app")
        #expect(state.project == "app")
        #expect(state.status == .needsApproval, "the hook knows more than the registry")
        #expect(state.tool == "Bash")
        #expect(state.firstSeen == t0)
    }

    @Test func aSessionWithoutHookEventsComesFromTheRegistry() throws {
        let merged = SessionMerge.merge(hooks: [], processes: [
            process(10, "busy", status: "busy", started: 0),
            process(11, "waiting", status: "waiting", started: 1),
            process(12, "idle", status: "idle", started: 2),
            process(13, "cli", status: "idle", entrypoint: "cli", started: 3),
        ])
        #expect(merged.map(\.sessionId) == ["busy", "waiting", "idle", "cli"])
        #expect(merged.map(\.status) == [.working, .needsApproval, .idle, .idle])
        #expect(merged.map(\.host) == [.vscode, .vscode, .vscode, .terminal])
        let first = try #require(merged.first)
        #expect(first.pid == 10)
        #expect(first.folder == "/Users/demo/app")
        #expect(first.firstSeen == t0)
        #expect(first.statusSince == t0.addingTimeInterval(5))
        #expect(first.startedConversation == nil, "unknown: the transcript decides")
    }

    @Test func aHookFileOfAnEarlierSessionInTheSameProcessIsDropped() {
        // /clear gives the process a new session id; the old file must not stay as a second lamp.
        let merged = SessionMerge.merge(hooks: [hook("old", pid: 10), hook("new", pid: 10)], processes: [process(10, "new")])
        #expect(merged.map(\.sessionId) == ["new"])
    }

    @Test func hookSessionsTheRegistryDoesNotKnowStay() {
        let merged = SessionMerge.merge(hooks: [hook("terminal", pid: 50), hook("no-pid", pid: nil)], processes: [process(10, "vscode")])
        #expect(Set(merged.map(\.sessionId)) == ["terminal", "no-pid", "vscode"])
    }

    @Test func onlyInteractiveProcessesCount() {
        let merged = SessionMerge.merge(hooks: [], processes: [process(10, "a"), process(11, "b", kind: "print"), process(12, "c", kind: nil)])
        #expect(merged.map(\.sessionId) == ["a", "c"])
    }
}
