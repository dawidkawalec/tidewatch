import Foundation

/// One Claude Code hook payload, decoded tolerantly: only the fields Tidewatch uses, and a
/// `tool_input` of an unexpected shape never fails the whole event.
public struct HookEvent: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
        case subagentStart = "SubagentStart"
        case preCompact = "PreCompact"
    }

    /// nil for events Tidewatch does not handle.
    public var kind: Kind?
    public var rawName: String
    public var sessionId: String
    public var cwd: String
    public var toolName: String?
    public var command: String?
    public var filePath: String?
    public var url: String?
    public var notificationType: String?
    public var message: String?
    public var sessionTitle: String?
    public var runningBackgroundTasks: Int

    public init(
        kind: Kind,
        sessionId: String,
        cwd: String,
        toolName: String? = nil,
        command: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        notificationType: String? = nil,
        message: String? = nil,
        sessionTitle: String? = nil,
        runningBackgroundTasks: Int = 0
    ) {
        self.kind = kind
        rawName = kind.rawValue
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.url = url
        self.notificationType = notificationType
        self.message = message
        self.sessionTitle = sessionTitle
        self.runningBackgroundTasks = runningBackgroundTasks
    }

    public static func decode(_ data: Data) throws -> HookEvent {
        try JSONDecoder().decode(Payload.self, from: data).event
    }
}

extension HookEvent {
    private struct Payload: Decodable {
        var event: HookEvent

        private enum Keys: String, CodingKey {
            case sessionId = "session_id"
            case cwd
            case name = "hook_event_name"
            case toolName = "tool_name"
            case toolInput = "tool_input"
            case notificationType = "notification_type"
            case message
            case sessionTitle = "session_title"
            case backgroundTasks = "background_tasks"
        }

        private enum ToolKeys: String, CodingKey {
            case command
            case filePath = "file_path"
            case notebookPath = "notebook_path"
            case url
        }

        private struct BackgroundTask: Decodable {
            var status: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let name = try container.decode(String.self, forKey: .name)
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let tool = try? container.nestedContainer(keyedBy: ToolKeys.self, forKey: .toolInput)
            let tasks = (try? container.decodeIfPresent([BackgroundTask].self, forKey: .backgroundTasks)) ?? []

            var event = HookEvent(
                kind: .stop,
                sessionId: sessionId,
                cwd: (try? container.decodeIfPresent(String.self, forKey: .cwd)) ?? "",
                toolName: try? container.decodeIfPresent(String.self, forKey: .toolName),
                command: try? tool?.decodeIfPresent(String.self, forKey: .command),
                filePath: (try? tool?.decodeIfPresent(String.self, forKey: .filePath))
                    ?? (try? tool?.decodeIfPresent(String.self, forKey: .notebookPath)),
                url: try? tool?.decodeIfPresent(String.self, forKey: .url),
                notificationType: try? container.decodeIfPresent(String.self, forKey: .notificationType),
                message: try? container.decodeIfPresent(String.self, forKey: .message),
                sessionTitle: try? container.decodeIfPresent(String.self, forKey: .sessionTitle),
                runningBackgroundTasks: tasks.filter { $0.status == "running" }.count
            )
            event.kind = Kind(rawValue: name)
            event.rawName = name
            self.event = event
        }
    }
}
