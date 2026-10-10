import Foundation
import Testing
@testable import TidewatchCore

struct SessionReducerTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func context(_ seconds: TimeInterval = 0, host: SessionHost = .vscode, pid: Int32? = 100) -> EventContext {
        EventContext(now: t0.addingTimeInterval(seconds), host: host, terminalApp: nil, pid: pid)
    }

    private func event(_ kind: HookEvent.Kind, tool: String? = nil, command: String? = nil, filePath: String? = nil,
                       notificationType: String? = nil, title: String? = nil, background: Int = 0) -> HookEvent {
        HookEvent(kind: kind, sessionId: "s-1", cwd: "/Users/demo/app", toolName: tool, command: command, filePath: filePath,
                  notificationType: notificationType, sessionTitle: title, runningBackgroundTasks: background)
    }

    /// Applies events in order, `step` seconds apart, and returns the last written state.
    private func run(_ events: [HookEvent], start: SessionState? = nil, step: TimeInterval = 1) -> SessionState? {
        var state = start
        for (index, e) in events.enumerated() {
            switch SessionReducer.reduce(state, e, context: context(Double(index) * step)) {
            case .write(let next): state = next
            case .delete: state = nil
            case .ignore: break
            }
        }
        return state
    }

    @Test func sessionStartCreatesAnIdleSession() throws {
        let state = try #require(run([event(.sessionStart, title: "Fix login")]))
        #expect(state.status == .idle)
        #expect(state.title == "Fix login")
        #expect(state.pid == 100)
        #expect(state.host == .vscode)
        #expect(state.firstSeen == t0)
    }

    @Test func promptMakesItWorkAndThinking() throws {
        let state = try #require(run([event(.sessionStart), event(.userPromptSubmit)]))
        #expect(state.status == .working)
        #expect(state.activity == .thinking)
        #expect(state.statusSince == t0.addingTimeInterval(1))
    }

    @Test func toolUseSetsActivityAndKeepsStatusSince() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.preToolUse, tool: "Bash", command: "npm test"), event(.postToolUse, tool: "Bash", command: "npm test")]))
        #expect(state.status == .working)
        #expect(state.activity == .runningTests)
        #expect(state.statusSince == t0)
        #expect(state.lastEvent == t0.addingTimeInterval(2))
    }

    @Test func eventsWithoutSessionStartStillCreateTheSession() throws {
        let state = try #require(run([event(.preToolUse, tool: "Edit", filePath: "/Users/demo/app/a.swift")]))
        #expect(state.status == .working)
        #expect(state.activity == .coding)
    }

    @Test func permissionRequestNeedsApprovalWithDetail() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.preToolUse, tool: "Bash", command: "npm install"), event(.permissionRequest, tool: "Bash", command: "npm install")]))
        #expect(state.status == .needsApproval)
        #expect(state.tool == "Bash")
        #expect(state.detail == "npm install")
        #expect(state.pendingApproval == "Bash|npm install")
    }

    @Test func matchingPostClearsApproval() throws {
        let state = try #require(run([event(.permissionRequest, tool: "Bash", command: "npm install"), event(.postToolUse, tool: "Bash", command: "npm install")]))
        #expect(state.status == .working)
        #expect(state.pendingApproval == nil)
        #expect(state.approvalResolvedAt == t0.addingTimeInterval(1))
    }

    @Test func failedMatchingPostClearsApprovalToo() throws {
        let state = try #require(run([event(.permissionRequest, tool: "Bash", command: "rm x"), event(.postToolUseFailure, tool: "Bash", command: "rm x")]))
        #expect(state.status == .working)
    }

    @Test func unrelatedPostKeepsApproval() throws {
        let state = try #require(run([
            event(.preToolUse, tool: "Read", filePath: "/a"),
            event(.permissionRequest, tool: "Bash", command: "npm install"),
            event(.postToolUse, tool: "Read", filePath: "/a"),
            event(.preToolUse, tool: "Grep"),
        ]))
        #expect(state.status == .needsApproval)
        #expect(state.detail == "npm install")
        #expect(state.activity == .readingCode)
    }

    @Test func askUserQuestionIsAnApprovalThatTheAnswerClears() throws {
        let waiting = try #require(run([event(.permissionRequest, tool: "AskUserQuestion")]))
        #expect(waiting.status == .needsApproval)
        #expect(waiting.tool == "AskUserQuestion")
        #expect(waiting.detail == nil)
        let answered = try #require(run([event(.postToolUse, tool: "AskUserQuestion")], start: waiting))
        #expect(answered.status == .working)
    }

    @Test func notificationFallbackSetsApprovalWhenPermissionRequestDidNotFire() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.notification, notificationType: "permission_prompt")]))
        #expect(state.status == .needsApproval)
        #expect(state.pendingApproval == nil)
        let cleared = try #require(run([event(.postToolUse, tool: "Bash", command: "x")], start: state))
        #expect(cleared.status == .working)
    }

    @Test func lateNotificationAfterResolvedApprovalIsIgnored() throws {
        let resolved = try #require(run([event(.permissionRequest, tool: "Bash", command: "a"), event(.postToolUse, tool: "Bash", command: "a")]))
        // 5 s after the resolution: inside the window.
        guard case .write(let late) = SessionReducer.reduce(resolved, event(.notification, notificationType: "permission_prompt"), context: context(6)) else {
            Issue.record("expected a write"); return
        }
        #expect(late.status == .working)
        // 30 s later: a new, real prompt.
        guard case .write(let real) = SessionReducer.reduce(resolved, event(.notification, notificationType: "permission_prompt"), context: context(31)) else {
            Issue.record("expected a write"); return
        }
        #expect(real.status == .needsApproval)
    }

    @Test func otherNotificationsAreIgnored() {
        #expect(SessionReducer.reduce(nil, event(.notification, notificationType: "auth_success"), context: context()) == .ignore)
    }

    @Test func idlePromptTurnsAnInterruptedTurnIdle() throws {
        // Esc mid-turn fires no Stop; Claude's idle prompt (after ~60 s) is the only signal.
        let state = try #require(run([event(.userPromptSubmit), event(.preToolUse, tool: "Bash", command: "npm test"), event(.notification, notificationType: "idle_prompt")]))
        #expect(state.status == .idle)
        #expect(state.tool == nil)
    }

    @Test func idlePromptNeverHidesApprovalOrReview() throws {
        let approval = try #require(run([event(.permissionRequest, tool: "Bash", command: "a"), event(.notification, notificationType: "idle_prompt")]))
        #expect(approval.status == .needsApproval)
        let review = try #require(run([event(.userPromptSubmit), event(.stop), event(.notification, notificationType: "idle_prompt")]))
        #expect(review.status == .awaitingReview)
    }

    @Test func stopAwaitsReviewAndCountsBackgroundTasks() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.permissionRequest, tool: "Bash", command: "a"), event(.stop, background: 2)]))
        #expect(state.status == .awaitingReview)
        #expect(state.backgroundTasks == 2)
        #expect(state.pendingApproval == nil)
        #expect(state.tool == nil)
        #expect(state.detail == nil)
    }

    @Test func subagentAndCompactKeepItWorking() throws {
        let agents = try #require(run([event(.userPromptSubmit), event(.subagentStart)]))
        #expect(agents.activity == .runningAgents)
        let compacting = try #require(run([event(.userPromptSubmit), event(.preCompact)]))
        #expect(compacting.activity == .compacting)
        #expect(compacting.status == .working)
    }

    @Test func resumedSessionKeepsItsStatus() throws {
        let working = try #require(run([event(.userPromptSubmit)]))
        let resumed = try #require(run([event(.sessionStart)], start: working))
        #expect(resumed.status == .working)
    }

    @Test func sessionEndDeletes() {
        #expect(SessionReducer.reduce(nil, event(.sessionEnd), context: context()) == .delete)
    }

    @Test func unknownEventIsIgnored() {
        var e = event(.stop)
        e.kind = nil
        #expect(SessionReducer.reduce(nil, e, context: context()) == .ignore)
    }

    @Test func cwdAndPidFollowTheLatestEvent() throws {
        let first = try #require(run([event(.userPromptSubmit)]))
        var moved = event(.preToolUse, tool: "Read")
        moved.cwd = "/Users/demo/other"
        guard case .write(let state) = SessionReducer.reduce(first, moved, context: EventContext(now: t0, host: .terminal, terminalApp: "iTerm.app", pid: 200)) else {
            Issue.record("expected a write"); return
        }
        #expect(state.cwd == "/Users/demo/other")
        #expect(state.pid == 200)
        #expect(state.host == .terminal)
        #expect(state.terminalApp == "iTerm.app")
    }

    @Test func emptyTitleNeverOverwritesARealOne() throws {
        let titled = try #require(run([event(.sessionStart, title: "Fix login")]))
        let again = try #require(run([event(.sessionStart, title: "  ")], start: titled))
        #expect(again.title == "Fix login")
    }
}
