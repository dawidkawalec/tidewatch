import Foundation
import Testing
@testable import TidewatchCore

/// Lamps only for sessions someone works in. The VS Code extension starts spare `claude` processes
/// that fire SessionStart and never get a prompt, and Claude Code's own helpers run inside
/// `~/.claude`: neither may show up as a session.
struct ConversationTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)
    private let home = "/Users/demo"

    private func context(_ seconds: TimeInterval = 0) -> EventContext {
        EventContext(now: t0.addingTimeInterval(seconds), host: .vscode, terminalApp: nil, pid: 100)
    }

    private func reduce(_ events: [HookEvent]) -> SessionState? {
        var state: SessionState?
        for (index, event) in events.enumerated() {
            if case .write(let next) = SessionReducer.reduce(state, event, context: context(Double(index))) { state = next }
        }
        return state
    }

    private func start(_ source: String?) -> HookEvent {
        HookEvent(kind: .sessionStart, sessionId: "s-1", cwd: "/Users/demo/app", source: source)
    }

    private func event(_ kind: HookEvent.Kind) -> HookEvent {
        HookEvent(kind: kind, sessionId: "s-1", cwd: "/Users/demo/app", toolName: kind == .preToolUse ? "Read" : nil)
    }

    @Test func decodesTheSessionStartSource() throws {
        let json = #"{"session_id":"s1","cwd":"/Users/demo/app","hook_event_name":"SessionStart","source":"resume","model":"x"}"#
        #expect(try HookEvent.decode(Data(json.utf8)).source == "resume")
        let other = #"{"session_id":"s1","cwd":"/Users/demo/app","hook_event_name":"Stop"}"#
        #expect(try HookEvent.decode(Data(other.utf8)).source == nil)
    }

    @Test func freshStartHasNoConversation() throws {
        for source in ["startup", "clear", nil] {
            let state = try #require(reduce([start(source)]))
            #expect(state.startedConversation == false, "source \(source ?? "nil")")
        }
    }

    @Test func resumedOrCompactedStartHasAConversation() throws {
        #expect(try #require(reduce([start("resume")])).startedConversation == true)
        #expect(try #require(reduce([start("compact")])).startedConversation == true)
    }

    @Test func thePromptStartsTheConversation() throws {
        let state = try #require(reduce([start("startup"), event(.userPromptSubmit)]))
        #expect(state.startedConversation == true)
    }

    /// A session already running when Tidewatch was connected is first seen mid-turn.
    @Test func aSessionFirstSeenMidTurnHasAConversation() throws {
        #expect(try #require(reduce([event(.preToolUse)])).startedConversation == true)
        #expect(try #require(reduce([event(.stop)])).startedConversation == true)
    }

    @Test func aLaterStartupKeepsTheConversation() throws {
        let state = try #require(reduce([start("startup"), event(.userPromptSubmit), start("startup")]))
        #expect(state.startedConversation == true)
    }

    /// State files written before this field existed leave it unknown (the transcript decides).
    @Test func olderStateFilesLeaveTheConversationUnknown() throws {
        var state = SessionState(sessionId: "s-1", cwd: "/Users/demo/app", host: .vscode, terminalApp: nil, pid: 1, now: t0)
        state.startedConversation = nil
        let data = try SessionCoding.encoder().encode(state)
        #expect(!String(decoding: data, as: UTF8.self).contains("startedConversation"))
        #expect(try SessionCoding.decoder().decode(SessionState.self, from: data).startedConversation == nil)
    }

    @Test func onlySessionsWithAConversationOutsideClaudesFolderAreShown() {
        var state = SessionState(sessionId: "s-1", cwd: "/Users/demo/app", host: .vscode, terminalApp: nil, pid: 1, now: t0)
        state.startedConversation = true
        #expect(DisplayRules.isShown(state, home: home))

        state.startedConversation = false
        #expect(!DisplayRules.isShown(state, home: home))

        state.startedConversation = true
        for cwd in ["/Users/demo/.claude", "/Users/demo/.claude/", "/Users/demo/.claude/projects/-Users-demo-app"] {
            state.root = cwd
            #expect(!DisplayRules.isShown(state, home: home), "\(cwd)")
        }
        for cwd in ["/Users/demo/.claude-tools", "/Users/demo/projects/.claude-app", "/Users/other/.claude/x"] {
            state.root = cwd
            #expect(DisplayRules.isShown(state, home: home), "\(cwd)")
        }
    }
}
