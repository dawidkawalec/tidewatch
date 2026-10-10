import Foundation

/// How a session state is shown at a given moment (spec 4.2 to 4.4). Pure: every function takes
/// `now`, so a render never depends on a timer having fired.
public enum DisplayRules {
    /// "Awaiting review" fades to "Idle" after this long.
    public static let reviewToIdle: TimeInterval = 10 * 60
    /// A session with no event for this long is dropped (crash without `SessionEnd`).
    public static let staleAfter: TimeInterval = 6 * 60 * 60

    public static func displayStatus(_ state: SessionState, now: Date, acknowledgedAt: Date?) -> SessionStatus {
        guard state.status == .awaitingReview else { return state.status }
        if let acknowledgedAt, acknowledgedAt >= state.lastEvent { return .idle }
        if now.timeIntervalSince(state.statusSince) > reviewToIdle { return .idle }
        return .awaitingReview
    }

    /// A session whose process is still alive is kept much longer: only this cap guards against a
    /// recycled pid keeping a crashed session on screen.
    public static let abandonedAfter: TimeInterval = 48 * 60 * 60

    /// The fallback for sessions with no known pid.
    public static func isStale(_ state: SessionState, now: Date) -> Bool {
        now.timeIntervalSince(state.lastEvent) > staleAfter
    }

    public static func isAbandoned(_ state: SessionState, now: Date) -> Bool {
        now.timeIntervalSince(state.lastEvent) > abandonedAfter
    }

    /// Whether a session gets a lamp: someone works in it (not a spare process the VS Code extension
    /// started) and it runs in a project, not inside Claude Code's own `~/.claude` folder.
    public static func isShown(_ state: SessionState, home: String) -> Bool {
        guard state.hasConversation else { return false }
        let claudeFolder = (home.hasSuffix("/") ? String(home.dropLast()) : home) + "/.claude"
        return state.cwd != claudeFolder && !state.cwd.hasPrefix(claudeFolder + "/")
    }

    /// Stable order: lamps never jump when a status changes.
    public static func ordered(_ sessions: [SessionState]) -> [SessionState] {
        sessions.sorted { ($0.firstSeen, $0.sessionId) < ($1.firstSeen, $1.sessionId) }
    }

    public static func statusLine(_ state: SessionState, status: SessionStatus) -> String {
        switch status {
        case .working:
            return activityLabel(state.activity)
        case .needsApproval:
            let base = state.tool == "AskUserQuestion" ? "Needs your answer" : "Needs approval"
            if let detail = state.detail, !detail.isEmpty { return "\(base) · \(detail)" }
            return base
        case .awaitingReview:
            switch state.backgroundTasks {
            case 0: return "Awaiting review"
            case 1: return "Awaiting review · 1 background task"
            default: return "Awaiting review · \(state.backgroundTasks) background tasks"
            }
        case .idle:
            return "Idle"
        }
    }

    public static func activityLabel(_ activity: SessionActivity) -> String {
        switch activity {
        case .runningTests: return "Running tests…"
        case .runningCommands: return "Running commands…"
        case .coding: return "Coding…"
        case .readingCode: return "Reading code…"
        case .researching: return "Researching…"
        case .runningAgents: return "Running agents…"
        case .usingTools: return "Using tools…"
        case .compacting: return "Compacting…"
        case .thinking, .working: return "Working…"
        }
    }

    /// "now", "2m", "3h", "2d".
    public static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(start))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    /// Row titles keyed by session id: the folder name, plus the title (or "#n") when several
    /// sessions share a folder.
    public static func names(for sessions: [SessionState]) -> [String: String] {
        let sorted = ordered(sessions)
        var counts: [String: Int] = [:]
        for session in sorted { counts[session.project, default: 0] += 1 }
        var seen: [String: Int] = [:]
        var names: [String: String] = [:]
        for session in sorted {
            guard counts[session.project, default: 0] > 1 else {
                names[session.id] = session.project
                continue
            }
            seen[session.project, default: 0] += 1
            if let title = session.title {
                names[session.id] = "\(session.project) · \(title)"
            } else {
                names[session.id] = "\(session.project) #\(seen[session.project, default: 1])"
            }
        }
        return names
    }
}
