import Foundation

/// What a tool call means for the status line.
public enum ActivityClassifier {
    public static func activity(forTool tool: String, command: String?) -> SessionActivity {
        switch tool {
        case "Bash", "BashOutput":
            if let command, isTestCommand(command) { return .runningTests }
            return .runningCommands
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return .coding
        case "Read", "Grep", "Glob", "LS":
            return .readingCode
        case "WebSearch", "WebFetch":
            return .researching
        case "Task", "Agent":
            return .runningAgents
        default:
            return tool.hasPrefix("mcp__") ? .usingTools : .working
        }
    }

    /// True for commands that run a test suite (`npm test`, `swift test`, `pytest`, ...), not for
    /// commands that only mention a "test" path.
    public static func isTestCommand(_ command: String) -> Bool {
        let range = NSRange(command.startIndex..., in: command)
        return testPattern.firstMatch(in: command, range: range) != nil
    }

    private static let testPattern = try! NSRegularExpression(
        pattern: #"(?:^|[\s;&|(])(?:(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test\b|(?:make|swift|cargo|go|deno|flutter|mix|dotnet)\s+test\b|xcodebuild\b[^;&|\n]*\stest\b|(?:npx\s+)?(?:jest|vitest|pytest|phpunit|rspec|mocha)\b|playwright\s+test\b)"#,
        options: [.caseInsensitive]
    )
}
