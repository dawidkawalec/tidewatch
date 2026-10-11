import Darwin
import Foundation
import TidewatchCore

/// What a session's transcript says: whether the conversation began, and its title.
struct TranscriptInfo: Equatable, Sendable {
    var exists: Bool
    var title: String?
}

/// What the store reads besides its own folder: Claude Code's registry of running processes,
/// the process table (a session's parent is its VS Code window) and the transcripts. Tests and
/// the design preview use `.none`, so they never see the real sessions on this Mac.
@MainActor
struct ClaudeSystem {
    var processes: () -> [ClaudeProcess]
    var parent: (Int32) -> Int32?
    var transcript: (SessionState) -> TranscriptInfo

    static let none = ClaudeSystem(
        processes: { [] },
        parent: { _ in nil },
        transcript: { _ in TranscriptInfo(exists: true, title: nil) }
    )

    static func live(home: String = NSHomeDirectory()) -> ClaudeSystem {
        let config = ClaudeRegistry.configDirectory(home: home)
        let registry = ClaudeRegistry.sessionsDirectory(config: config)
        let transcripts = TranscriptReader(config: config)
        return ClaudeSystem(
            processes: { ClaudeRegistry.load(directory: registry).filter(ProcessTable.isRunning) },
            parent: ProcessTable.parent,
            transcript: transcripts.info
        )
    }
}

enum ProcessTable {
    /// A registry entry whose process still runs; a recycled pid started at another time.
    static func isRunning(_ process: ClaudeProcess) -> Bool {
        guard ProcessLiveness.isAlive(process.pid) else { return false }
        guard let started = startTime(of: process.pid) else { return true }
        return abs(started.timeIntervalSince(process.startedAt)) < 120
    }

    static func parent(of pid: Int32) -> Int32? {
        info(pid).map { $0.kp_eproc.e_ppid }
    }

    static func startTime(of pid: Int32) -> Date? {
        info(pid).map {
            let time = $0.kp_proc.p_un.__p_starttime
            return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
        }
    }

    private static func info(_ pid: Int32) -> kinfo_proc? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return info
    }
}

/// Reads only the end of a transcript, and again only when the file changed and the last read is
/// a few seconds old: a working session appends to it all the time.
@MainActor
final class TranscriptReader {
    static let rereadAfter: TimeInterval = 10
    /// A missing transcript is looked for again after this long (it appears with the first prompt).
    static let missingRetry: TimeInterval = 60

    private struct Entry {
        var url: URL?
        var size: Int = -1
        var modified: Date = .distantPast
        var readAt: Date = .distantPast
        var info = TranscriptInfo(exists: false, title: nil)
    }

    private let config: URL
    private let clock: () -> Date
    private var entries: [String: Entry] = [:]

    init(config: URL, clock: @escaping () -> Date = { Date() }) {
        self.config = config
        self.clock = clock
    }

    func info(for state: SessionState) -> TranscriptInfo {
        let now = clock()
        var entry = entries[state.sessionId] ?? Entry()
        if entry.url == nil {
            guard now.timeIntervalSince(entry.readAt) >= Self.missingRetry else { return entry.info }
            entry.readAt = now
            entry.url = locate(state)
            if entry.url == nil {
                entries[state.sessionId] = entry
                return entry.info
            }
        }
        guard let url = entry.url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue else {
            entries[state.sessionId] = Entry(readAt: now)
            return TranscriptInfo(exists: false, title: nil)
        }
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        let changed = size != entry.size || modified != entry.modified
        if changed, now.timeIntervalSince(entry.readAt) >= Self.rereadAfter || !entry.info.exists {
            entry.size = size
            entry.modified = modified
            entry.readAt = now
            entry.info = TranscriptInfo(exists: true, title: Self.title(at: url, size: size) ?? entry.info.title)
        }
        entries[state.sessionId] = entry
        return entry.info
    }

    /// Where Claude Code keeps the transcript; a session first seen after the agent changed folder
    /// is looked up by its id in every project folder.
    private func locate(_ state: SessionState) -> URL? {
        let expected = ClaudeRegistry.transcriptURL(config: config, cwd: state.folder, sessionId: state.sessionId)
        if FileManager.default.fileExists(atPath: expected.path) { return expected }
        let projects = config.appendingPathComponent("projects", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders
            .map { $0.appendingPathComponent("\(state.sessionId).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func title(at url: URL, size: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let start = max(0, size - ClaudeRegistry.titleTailBytes)
        guard (try? handle.seek(toOffset: UInt64(start))) != nil, let data = try? handle.readToEnd() else { return nil }
        return ClaudeRegistry.title(inTranscriptTail: data)
    }
}
