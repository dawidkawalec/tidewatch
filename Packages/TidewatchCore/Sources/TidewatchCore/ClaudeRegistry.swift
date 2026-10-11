import Foundation

/// One running Claude Code process, as Claude Code itself lists it in `~/.claude/sessions/<pid>.json`.
public struct ClaudeProcess: Sendable, Equatable {
    public var pid: Int32
    public var sessionId: String
    /// Where the process started: the VS Code window's folder.
    public var cwd: String
    /// "interactive" for a tab or a terminal session.
    public var kind: String?
    /// "claude-vscode" for the VS Code extension, "cli" for a terminal.
    public var entrypoint: String?
    /// "busy", "waiting" or "idle".
    public var status: String?
    public var waitingFor: String?
    public var startedAt: Date
    public var updatedAt: Date?
    public var statusUpdatedAt: Date?

    public init(pid: Int32, sessionId: String, cwd: String, kind: String?, entrypoint: String?, status: String?, waitingFor: String?, startedAt: Date, updatedAt: Date?, statusUpdatedAt: Date?) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.kind = kind
        self.entrypoint = entrypoint
        self.status = status
        self.waitingFor = waitingFor
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.statusUpdatedAt = statusUpdatedAt
    }
}

/// Claude Code's own files: the registry of running processes and the transcripts. Undocumented,
/// so every read is tolerant: anything unexpected is skipped and Tidewatch falls back to the hooks.
public enum ClaudeRegistry {
    /// How much of a transcript's end is searched for its title.
    public static let titleTailBytes = 256 * 1024

    private struct Raw: Decodable {
        var pid: Int32
        var sessionId: String
        var cwd: String
        var kind: String?
        var entrypoint: String?
        var status: String?
        var waitingFor: String?
        var startedAt: Double
        var updatedAt: Double?
        var statusUpdatedAt: Double?
    }

    public static func configDirectory(home: String = NSHomeDirectory(), environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".claude", isDirectory: true)
    }

    public static func sessionsDirectory(config: URL) -> URL {
        config.appendingPathComponent("sessions", isDirectory: true)
    }

    public static func decode(_ data: Data) -> ClaudeProcess? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data),
              SessionFileStore.isValidSessionId(raw.sessionId), raw.pid > 0, !raw.cwd.isEmpty else { return nil }
        func date(_ milliseconds: Double?) -> Date? {
            milliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        return ClaudeProcess(
            pid: raw.pid,
            sessionId: raw.sessionId,
            cwd: raw.cwd,
            kind: raw.kind,
            entrypoint: raw.entrypoint,
            status: raw.status,
            waitingFor: raw.waitingFor,
            startedAt: Date(timeIntervalSince1970: raw.startedAt / 1000),
            updatedAt: date(raw.updatedAt),
            statusUpdatedAt: date(raw.statusUpdatedAt)
        )
    }

    /// Every readable `<pid>.json` of the folder (the `.key` files next to them are never read).
    public static func load(directory: URL) -> [ClaudeProcess] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap(decode) }
            .sorted { $0.pid < $1.pid }
    }

    /// Claude Code's folder name for a project: every character other than a letter or a digit
    /// becomes "-".
    public static func projectSlug(_ cwd: String) -> String {
        String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    public static func transcriptURL(config: URL, cwd: String, sessionId: String) -> URL {
        config
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectSlug(cwd), isDirectory: true)
            .appendingPathComponent("\(sessionId).jsonl")
    }

    /// The conversation's title (the one on the VS Code tab) from the end of its transcript: a
    /// title the user gave wins over the generated one, and the latest of each counts.
    public static func title(inTranscriptTail data: Data) -> String? {
        var custom: String?
        var generated: String?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.count < 4096, let text = String(data: Data(line), encoding: .utf8), text.contains("-title\"") else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "custom-title": custom = clean(object["customTitle"]) ?? custom
            case "ai-title": generated = clean(object["aiTitle"]) ?? generated
            default: break
            }
        }
        return custom ?? generated
    }

    private static func clean(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
