import Foundation

/// One session's current state: the content of `sessions/<sessionId>.json`. Written only by the
/// hook helper (through `SessionFileStore`), read by the app.
public struct SessionState: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchema = 1

    public var schema: Int
    public var sessionId: String
    /// Where the last event ran; follows the agent's `cd`.
    public var cwd: String
    /// Where the session started (the VS Code window's folder). nil in files from before 0.4.0.
    public var root: String?
    public var title: String?
    public var host: SessionHost
    /// `TERM_PROGRAM` of a terminal session ("iTerm.app", "Apple_Terminal", ...).
    public var terminalApp: String?
    /// The Claude Code process (the helper's parent), used to drop crashed sessions.
    public var pid: Int32?
    public var status: SessionStatus
    public var activity: SessionActivity
    public var tool: String?
    public var detail: String?
    /// `ApprovalDetail.signature` of the tool call waiting for approval.
    public var pendingApproval: String?
    /// When the last approval was resolved; a late `Notification permission_prompt` is ignored.
    public var approvalResolvedAt: Date?
    /// Running background tasks reported by the last `Stop`.
    public var backgroundTasks: Int
    /// Changes only when `status` changes.
    public var statusSince: Date
    public var firstSeen: Date
    /// Changes on every event.
    public var lastEvent: Date
    /// False from a fresh SessionStart until the first prompt or tool call: the VS Code extension
    /// opens empty tabs that may never get one. nil (files from before 0.3.0, sessions known only
    /// from Claude Code's registry) is unknown: `DisplayRules.isShown` asks the transcript.
    public var startedConversation: Bool?

    public var id: String { sessionId }

    /// The session's project folder: it names the lamp and is what a click opens.
    public var folder: String { root ?? cwd }

    /// The project folder's name ("captylo-app").
    public var project: String {
        let name = URL(fileURLWithPath: folder).lastPathComponent
        return name.isEmpty ? folder : name
    }

    public init(sessionId: String, cwd: String, host: SessionHost, terminalApp: String?, pid: Int32?, now: Date) {
        schema = Self.currentSchema
        self.sessionId = sessionId
        self.cwd = cwd
        root = cwd.isEmpty ? nil : cwd
        title = nil
        self.host = host
        self.terminalApp = terminalApp
        self.pid = pid
        status = .idle
        activity = .working
        tool = nil
        detail = nil
        pendingApproval = nil
        approvalResolvedAt = nil
        backgroundTasks = 0
        statusSince = now
        firstSeen = now
        lastEvent = now
        startedConversation = false
    }
}
