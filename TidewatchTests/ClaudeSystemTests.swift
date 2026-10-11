import Foundation
import Testing
import TidewatchCore
@testable import Tidewatch

@MainActor
struct ClaudeSystemTests {
    private func config() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tw-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func state(_ id: String, folder: String) -> SessionState {
        SessionState(sessionId: id, cwd: folder, host: .vscode, terminalApp: nil, pid: nil, now: Date())
    }

    private func writeTranscript(_ config: URL, cwd: String, id: String, _ lines: [String]) throws {
        let url = ClaudeRegistry.transcriptURL(config: config, cwd: cwd, sessionId: id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
    }

    @Test func readsTheTitleOfATranscript() throws {
        let config = try config()
        try writeTranscript(config, cwd: "/w/atlas", id: "s-1", [#"{"type":"user"}"#, #"{"type":"ai-title","aiTitle":"Checkout redesign"}"#])
        let reader = TranscriptReader(config: config)
        #expect(reader.info(for: state("s-1", folder: "/w/atlas")) == TranscriptInfo(exists: true, title: "Checkout redesign"))
    }

    @Test func aTabWithoutATranscriptHasNoConversation() throws {
        let reader = TranscriptReader(config: try config())
        #expect(reader.info(for: state("empty", folder: "/w/atlas")) == TranscriptInfo(exists: false, title: nil))
    }

    /// An older hook file may carry the folder the agent moved to; the transcript is found by id.
    @Test func findsATranscriptUnderAnotherFolder() throws {
        let config = try config()
        try writeTranscript(config, cwd: "/w/session-widget", id: "s-2", [#"{"type":"ai-title","aiTitle":"Monitor sesji"}"#])
        let reader = TranscriptReader(config: config)
        #expect(reader.info(for: state("s-2", folder: "/w/kawalec")).title == "Monitor sesji")
    }

    @Test func aMissingTranscriptIsLookedForAgainLater() throws {
        let config = try config()
        var now = Date(timeIntervalSince1970: 1_791_620_000)
        let reader = TranscriptReader(config: config, clock: { now })
        let tab = state("s-3", folder: "/w/app")
        #expect(!reader.info(for: tab).exists)
        try writeTranscript(config, cwd: "/w/app", id: "s-3", [#"{"type":"user"}"#])
        #expect(!reader.info(for: tab).exists, "cached for a while")
        now = now.addingTimeInterval(TranscriptReader.missingRetry + 1)
        #expect(reader.info(for: tab).exists)
    }

    @Test func processTableKnowsThisProcess() throws {
        #expect(ProcessTable.parent(of: getpid()) == getppid())
        let started = try #require(ProcessTable.startTime(of: getpid()))
        #expect(started <= Date())
        #expect(ProcessTable.parent(of: 0) == nil)
    }

    @Test func aRegistryEntryOfARecycledPidIsNotRunning() {
        let me = ClaudeProcess(pid: getpid(), sessionId: "s", cwd: "/w", kind: "interactive", entrypoint: "claude-vscode", status: "idle", waitingFor: nil, startedAt: ProcessTable.startTime(of: getpid()) ?? Date(), updatedAt: nil, statusUpdatedAt: nil)
        #expect(ProcessTable.isRunning(me))
        var recycled = me
        recycled.startedAt = me.startedAt.addingTimeInterval(-86_400)
        #expect(!ProcessTable.isRunning(recycled))
    }

    /// The restart script waits for the old process to quit before it opens the app again.
    @Test func restartWaitsForTheOldProcessToQuit() throws {
        let old = Process()
        old.executableURL = URL(fileURLWithPath: "/bin/sleep")
        old.arguments = ["0.6"]
        try old.run()
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/bin/sh")
        restart.arguments = AppRestarter.arguments(appPath: "/nonexistent/Tidewatch-test.app", pid: old.processIdentifier)
        restart.standardError = FileHandle.nullDevice
        let start = Date()
        try restart.run()
        restart.waitUntilExit()
        #expect(Date().timeIntervalSince(start) >= 0.4)
        #expect(!old.isRunning)
    }
}
