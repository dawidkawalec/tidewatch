import Foundation
import Testing
@testable import TidewatchCore

/// Lamps grouped by VS Code window: the tabs of one window sit together, a window with several
/// tabs names each by its conversation, and a session's name never follows the agent's `cd`.
struct WindowGroupingTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func state(_ id: String, cwd: String, firstSeen: TimeInterval, title: String? = nil) -> SessionState {
        var state = SessionState(sessionId: id, cwd: cwd, host: .vscode, terminalApp: nil, pid: nil, now: t0.addingTimeInterval(firstSeen))
        state.title = title
        state.startedConversation = true
        return state
    }

    @Test func groupsFollowTheirOldestSessionAndKeepTheirOrder() {
        let sessions = [
            state("c", cwd: "/w/atlas", firstSeen: 30),
            state("a", cwd: "/w/promo", firstSeen: 10),
            state("b", cwd: "/w/atlas", firstSeen: 20),
            state("d", cwd: "/w/promo", firstSeen: 40),
        ]
        let window = ["a": "w1", "d": "w1", "b": "w2", "c": "w2"]
        let groups = DisplayRules.grouped(sessions) { window[$0.sessionId]! }
        #expect(groups.map { $0.map(\.sessionId) } == [["a", "d"], ["b", "c"]])
    }

    @Test func aWindowWithOneTabIsNamedAfterItsFolder() {
        let names = DisplayRules.rowNames(in: [state("a", cwd: "/w/promo-kit", firstSeen: 0, title: "Skills audit")])
        #expect(names == ["a": "promo-kit"])
    }

    @Test func tabsOfOneWindowAreNamedAfterTheirConversations() {
        let names = DisplayRules.rowNames(in: [
            state("a", cwd: "/w/atlas", firstSeen: 0, title: "Checkout redesign"),
            state("b", cwd: "/w/atlas", firstSeen: 1),
            state("c", cwd: "/w/atlas", firstSeen: 2),
        ])
        #expect(names == ["a": "Checkout redesign", "b": "atlas #2", "c": "atlas #3"])
    }

    @Test func equalNamesAcrossWindowsAreNumbered() {
        let names = DisplayRules.names(for: [
            [state("a", cwd: "/w/app", firstSeen: 0)],
            [state("b", cwd: "/w/site", firstSeen: 1)],
            [state("c", cwd: "/w/app", firstSeen: 2)],
        ])
        #expect(names == ["a": "app #1", "b": "site", "c": "app #2"])
    }

    @Test func theFolderIsWhereTheSessionStartedNotWhereTheAgentWent() throws {
        let start = HookEvent(kind: .sessionStart, sessionId: "s", cwd: "/w/session-widget", source: "startup")
        let prompt = HookEvent(kind: .userPromptSubmit, sessionId: "s", cwd: "/w/other-repo")
        let context = EventContext(now: t0, host: .vscode, terminalApp: nil, pid: 1)
        guard case .write(let started) = SessionReducer.reduce(nil, start, context: context),
              case .write(let moved) = SessionReducer.reduce(started, prompt, context: context) else {
            Issue.record("no state")
            return
        }
        #expect(moved.cwd == "/w/other-repo")
        #expect(moved.folder == "/w/session-widget")
        #expect(moved.project == "session-widget")
    }

    @Test func filesFromBeforeTheFolderFieldUseTheirCwd() throws {
        let json = #"{"schema":1,"sessionId":"s","cwd":"/w/app","host":"vscode","status":"idle","activity":"working","backgroundTasks":0,"statusSince":"2026-10-10T19:49:27.177Z","firstSeen":"2026-10-10T19:49:27.177Z","lastEvent":"2026-10-10T19:49:27.177Z"}"#
        let state = try SessionCoding.decoder().decode(SessionState.self, from: Data(json.utf8))
        #expect(state.folder == "/w/app")
    }

    @Test func aSessionOfUnknownStartIsShownOnlyWithATranscript() {
        var legacy = state("s", cwd: "/w/app", firstSeen: 0)
        legacy.startedConversation = nil
        #expect(DisplayRules.isShown(legacy, home: "/Users/demo", hasTranscript: true))
        #expect(!DisplayRules.isShown(legacy, home: "/Users/demo", hasTranscript: false))
        var fresh = legacy
        fresh.startedConversation = false
        #expect(!DisplayRules.isShown(fresh, home: "/Users/demo", hasTranscript: true))
    }

    @Test func aProjectSessionStaysShownWhileTheAgentWorksInsideClaudesFolder() {
        var state = state("s", cwd: "/w/app", firstSeen: 0)
        state.cwd = "/Users/demo/.claude/sessions"
        #expect(DisplayRules.isShown(state, home: "/Users/demo"))
    }
}
