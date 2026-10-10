/// What a session is doing, as the lamps show it.
public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case working
    case needsApproval
    case awaitingReview
    case idle
}

/// What a working session is busy with. Drives the status line ("Running tests…").
public enum SessionActivity: String, Codable, Sendable, CaseIterable {
    case thinking
    case runningTests
    case runningCommands
    case coding
    case readingCode
    case researching
    case runningAgents
    case usingTools
    case compacting
    case working
}

/// Where the session runs, which decides what a click opens.
public enum SessionHost: String, Codable, Sendable {
    case vscode
    case terminal
}
