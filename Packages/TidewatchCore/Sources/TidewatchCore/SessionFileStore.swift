import Foundation

public enum SessionFileStoreError: Error, Equatable {
    case invalidSessionId(String)
    case lockFailed(Int32)
}

/// The sessions folder. Each event is applied under an exclusive `flock` on `<id>.lock` and
/// written with an atomic replace, so parallel hook processes never interleave and a reader
/// never sees half a file.
public struct SessionFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Claude Code session ids are UUIDs; anything with other characters is refused so an id can
    /// never point outside the folder.
    public static func isValidSessionId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public func fileURL(for sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).json")
    }

    private func lockURL(for sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).lock")
    }

    @discardableResult
    public func apply(_ event: HookEvent, context: EventContext) throws -> ReduceOutcome {
        guard Self.isValidSessionId(event.sessionId) else {
            throw SessionFileStoreError.invalidSessionId(event.sessionId)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(lockURL(for: event.sessionId).path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SessionFileStoreError.lockFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SessionFileStoreError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }

        let url = fileURL(for: event.sessionId)
        let outcome = SessionReducer.reduce(read(url), event, context: context)
        switch outcome {
        case .write(let state):
            try write(state, to: url)
        case .delete:
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: lockURL(for: event.sessionId))
        case .ignore:
            break
        }
        return outcome
    }

    public func read(_ url: URL) -> SessionState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SessionCoding.decoder().decode(SessionState.self, from: data)
    }

    public func write(_ state: SessionState, to url: URL) throws {
        let data = try SessionCoding.encoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

    /// Every readable session file; unreadable or foreign files are skipped.
    public func loadAll() -> [SessionState] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "json" }.compactMap(read)
    }

    public func remove(sessionId: String) {
        guard Self.isValidSessionId(sessionId) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: sessionId))
        try? FileManager.default.removeItem(at: lockURL(for: sessionId))
    }
}
