import Foundation

/// One session's current state: the content of `sessions/<sessionId>.json`. Written only by the
/// hook helper (through `SessionFileStore`), read by the app.
public struct SessionState: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchema = 1

    public var schema: Int
    public var sessionId: String
    public var cwd: String
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
    /// starts spare processes that never get one. nil (files from before 0.3.0) counts as true.
    public var startedConversation: Bool?

    public var id: String { sessionId }

    public var hasConversation: Bool { startedConversation ?? true }

    /// The project folder's name ("captylo-app"), the row title.
    public var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    public init(sessionId: String, cwd: String, host: SessionHost, terminalApp: String?, pid: Int32?, now: Date) {
        schema = Self.currentSchema
        self.sessionId = sessionId
        self.cwd = cwd
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
