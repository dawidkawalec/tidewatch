import Foundation
import Testing
import TidewatchCore
@testable import Tidewatch

@MainActor
struct SessionStoreTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_791_620_000)
    }

    final class Liveness: @unchecked Sendable {
        var alive: Set<Int32> = []
    }

    private let clock = Clock()
    private let liveness = Liveness()
    private let files: SessionFileStore
    private let defaults: UserDefaults

    init() {
        files = SessionFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("tw-sessions-\(UUID().uuidString)", isDirectory: true))
        try? FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "tw-tests-\(UUID().uuidString)")!
    }

    private func makeStore() -> SessionStore {
        let clock = clock
        let liveness = liveness
        return SessionStore(
            fileStore: files,
            acknowledged: AcknowledgedStore(defaults: defaults),
            isAlive: { liveness.alive.contains($0) },
            clock: { clock.now }
        )
    }

    private func put(_ id: String, _ status: SessionStatus, cwd: String = "/Users/demo/app", pid: Int32? = nil, firstSeen: TimeInterval = 0, lastEvent: TimeInterval = 0, conversation: Bool = true) throws {
        var state = SessionState(sessionId: id, cwd: cwd, host: .vscode, terminalApp: nil, pid: pid, now: clock.now.addingTimeInterval(firstSeen))
        state.startedConversation = conversation
        state.status = status
        state.statusSince = clock.now.addingTimeInterval(lastEvent)
        state.lastEvent = clock.now.addingTimeInterval(lastEvent)
        try files.write(state, to: files.fileURL(for: id))
    }

    @Test func loadsSessionsInStableOrderWithNames() throws {
        try put("b", .working, cwd: "/Users/demo/site", firstSeen: 10)
        try put("a", .needsApproval, cwd: "/Users/demo/app", firstSeen: 5)
        let store = makeStore()
        store.reload()
        #expect(store.sessions.map(\.id) == ["a", "b"])
        #expect(store.sessions.map(\.name) == ["app", "site"])
        #expect(store.sessions.map(\.status) == [.needsApproval, .working])
    }

    /// A spare VS Code process (no prompt yet) and a Claude Code helper inside ~/.claude get no
    /// lamp. Their files stay: the spare one shows up as soon as someone types in it.
    @Test func hidesSessionsWithoutAConversationOrInsideClaudesFolder() throws {
        try put("real", .working)
        try put("spare", .idle, conversation: false)
        try put("helper", .idle, cwd: "/Users/demo/.claude/projects/-Users-demo-app")
        let store = SessionStore(fileStore: files, acknowledged: AcknowledgedStore(defaults: defaults), isAlive: { _ in true }, clock: { [clock] in clock.now }, home: "/Users/demo")
        store.reload()
        #expect(store.sessions.map(\.id) == ["real"])
        #expect(FileManager.default.fileExists(atPath: files.fileURL(for: "spare").path))
    }

    @Test func dropsDeadProcessesAndDeletesTheirFiles() throws {
        liveness.alive = [100]
        try put("alive", .working, pid: 100)
        try put("dead", .working, pid: 200)
        try put("unknown-pid", .working, pid: nil)
        let store = makeStore()
        store.reload()
        #expect(Set(store.sessions.map(\.id)) == ["alive", "unknown-pid"])
        #expect(!FileManager.default.fileExists(atPath: files.fileURL(for: "dead").path))
    }

    @Test func dropsStaleSessions() throws {
        try put("old", .idle, lastEvent: -7 * 3600)
        try put("fresh", .idle, lastEvent: -60)
        let store = makeStore()
        store.reload()
        #expect(store.sessions.map(\.id) == ["fresh"])
        #expect(!FileManager.default.fileExists(atPath: files.fileURL(for: "old").path))
    }

    @Test func liveIdleSessionSurvivesTheSixHourRule() throws {
        liveness.alive = [100]
        try put("overnight", .idle, pid: 100, lastEvent: -10 * 3600)
        try put("abandoned", .idle, pid: 100, lastEvent: -49 * 3600)
        let store = makeStore()
        store.reload()
        #expect(store.sessions.map(\.id) == ["overnight"])
    }

    @Test func noTransitionsOnTheFirstLoadThenOnePerChange() throws {
        try put("a", .working)
        let store = makeStore()
        var transitions: [SessionTransition] = []
        store.onTransition = { transitions.append($0) }
        store.reload()
        #expect(transitions.isEmpty)

        try put("a", .needsApproval)
        try put("b", .awaitingReview, firstSeen: 1)
        store.reload()
        #expect(transitions == [
            SessionTransition(sessionId: "a", from: .working, to: .needsApproval),
            SessionTransition(sessionId: "b", from: nil, to: .awaitingReview),
        ])

        store.reload()
        #expect(transitions.count == 2)
    }

    @Test func acknowledgingAwaitingReviewShowsIdleWithoutATransitionCue() throws {
        try put("a", .awaitingReview)
        let store = makeStore()
        store.reload()
        let session = try #require(store.sessions.first)
        #expect(session.status == .awaitingReview)
        store.acknowledge(session)
        #expect(store.sessions.first?.status == .idle)
    }

    @Test func awaitingReviewFadesToIdleWithTime() throws {
        try put("a", .awaitingReview)
        let store = makeStore()
        store.reload()
        clock.now = clock.now.addingTimeInterval(11 * 60)
        store.reload()
        #expect(store.sessions.first?.status == .idle)
    }

    @Test func acknowledgementsSurviveAStoreRestart() throws {
        try put("a", .awaitingReview)
        let first = makeStore()
        first.reload()
        first.acknowledge(try #require(first.sessions.first))
        let second = makeStore()
        second.reload()
        #expect(second.sessions.first?.status == .idle)
    }

    @Test func livenessOfThisProcessIsTrue() {
        #expect(ProcessLiveness.isAlive(getpid()))
        #expect(!ProcessLiveness.isAlive(0))
        #expect(!ProcessLiveness.isAlive(-1))
    }
}
