import Foundation

/// Short, human detail of a tool call waiting for approval, and a signature that identifies the
/// same call in a later `PostToolUse` (the `PermissionRequest` payload has no `tool_use_id`).
public enum ApprovalDetail {
    public static let maxLength = 60

    public static func describe(_ event: HookEvent) -> String? {
        guard let tool = event.toolName else { return nil }
        switch tool {
        case "AskUserQuestion":
            return nil
        case "Bash":
            return event.command.map { shorten(firstLine($0)) }
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read":
            return event.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }
        case "WebFetch":
            return event.url.flatMap { URL(string: $0)?.host() }
        default:
            if tool.hasPrefix("mcp__"), let last = tool.components(separatedBy: "__").last {
                return last
            }
            return tool
        }
    }

    public static func signature(_ event: HookEvent) -> String {
        "\(event.toolName ?? "")|\(event.command ?? event.filePath ?? event.url ?? "")"
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func shorten(_ text: String) -> String {
        text.count <= maxLength ? text : String(text.prefix(maxLength - 1)) + "…"
    }
}
