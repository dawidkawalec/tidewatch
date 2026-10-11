import Foundation
import Testing
@testable import TidewatchCore

struct DisplayRulesTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func session(_ id: String, _ cwd: String = "/Users/demo/app", status: SessionStatus = .working, firstSeen: TimeInterval = 0, title: String? = nil) -> SessionState {
        var s = SessionState(sessionId: id, cwd: cwd, host: .vscode, terminalApp: nil, pid: nil, now: t0.addingTimeInterval(firstSeen))
        s.status = status
        s.title = title
        return s
    }

    @Test func awaitingReviewTurnsIdleAfterTenMinutes() {
        var s = session("a", status: .awaitingReview)
        s.statusSince = t0
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(599), acknowledgedAt: nil) == .awaitingReview)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(601), acknowledgedAt: nil) == .idle)
    }

    @Test func acknowledgedAwaitingReviewIsIdleUntilTheNextEvent() {
        var s = session("a", status: .awaitingReview)
        s.lastEvent = t0
        #expect(DisplayRules.displayStatus(s, now: t0, acknowledgedAt: t0) == .idle)
        s.lastEvent = t0.addingTimeInterval(5)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(5), acknowledgedAt: t0) == .awaitingReview)
    }

    @Test func acknowledgementNeverHidesApprovalOrWork() {
        let approval = session("a", status: .needsApproval)
        #expect(DisplayRules.displayStatus(approval, now: t0.addingTimeInterval(3600), acknowledgedAt: t0.addingTimeInterval(3600)) == .needsApproval)
        let working = session("b", status: .working)
        #expect(DisplayRules.displayStatus(working, now: t0.addingTimeInterval(3600), acknowledgedAt: t0.addingTimeInterval(3600)) == .working)
    }

    @Test func staleAfterSixHoursWithoutEvents() {
        let s = session("a")
        #expect(!DisplayRules.isStale(s, now: t0.addingTimeInterval(6 * 3600 - 1)))
        #expect(DisplayRules.isStale(s, now: t0.addingTimeInterval(6 * 3600 + 1)))
    }

    @Test func abandonedAfterTwoDaysEvenWithALivePid() {
        let s = session("a")
        #expect(!DisplayRules.isAbandoned(s, now: t0.addingTimeInterval(47 * 3600)))
        #expect(DisplayRules.isAbandoned(s, now: t0.addingTimeInterval(49 * 3600)))
    }

    @Test func orderIsStableByFirstSeenThenId() {
        let list = [session("c", firstSeen: 20), session("b", firstSeen: 10), session("a", firstSeen: 10)]
        #expect(DisplayRules.ordered(list).map(\.sessionId) == ["a", "b", "c"])
    }

    @Test func statusLines() {
        var s = session("a", status: .working)
        s.activity = .runningTests
        #expect(DisplayRules.statusLine(s, status: .working) == "Running tests…")
        s.activity = .thinking
        #expect(DisplayRules.statusLine(s, status: .working) == "Working…")
        s.tool = "Bash"
        s.detail = "npm install"
        #expect(DisplayRules.statusLine(s, status: .needsApproval) == "Needs approval · npm install")
        s.tool = "AskUserQuestion"
        s.detail = nil
        #expect(DisplayRules.statusLine(s, status: .needsApproval) == "Needs your answer")
        s.backgroundTasks = 0
        #expect(DisplayRules.statusLine(s, status: .awaitingReview) == "Awaiting review")
        s.backgroundTasks = 1
        #expect(DisplayRules.statusLine(s, status: .awaitingReview) == "Awaiting review · 1 background task")
        s.backgroundTasks = 3
        #expect(DisplayRules.statusLine(s, status: .awaitingReview) == "Awaiting review · 3 background tasks")
        #expect(DisplayRules.statusLine(s, status: .idle) == "Idle")
    }

    @Test func everyActivityHasALabel() {
        for activity in SessionActivity.allCases {
            #expect(DisplayRules.activityLabel(activity).hasSuffix("…"))
        }
        #expect(DisplayRules.activityLabel(.compacting) == "Compacting…")
    }

    /// The fade time is the user's choice; nil keeps the lamp until the session is opened.
    @Test func awaitingReviewFadesAfterTheChosenTimeOrNever() {
        let s = session("a", status: .awaitingReview)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(301), acknowledgedAt: nil, reviewFade: 300) == .idle)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(299), acknowledgedAt: nil, reviewFade: 300) == .awaitingReview)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(86_400), acknowledgedAt: nil, reviewFade: nil) == .awaitingReview)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(86_400), acknowledgedAt: t0, reviewFade: nil) == .idle)
    }

    @Test func elapsedIsCompact() {
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(20)) == "now")
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(125)) == "2m")
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(3 * 3600 + 5)) == "3h")
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(2 * 86_400)) == "2d")
        #expect(DisplayRules.elapsed(since: t0.addingTimeInterval(30), now: t0) == "now")
    }
}
