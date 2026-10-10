import Foundation

/// Facts about the hook process that are not in the payload.
public struct EventContext: Sendable, Equatable {
    public var now: Date
    public var host: SessionHost
    public var terminalApp: String?
    public var pid: Int32?

    public init(now: Date, host: SessionHost, terminalApp: String?, pid: Int32?) {
        self.now = now
        self.host = host
        self.terminalApp = terminalApp
        self.pid = pid
    }
}

public enum ReduceOutcome: Sendable, Equatable {
    case write(SessionState)
    case delete
    case ignore
}

/// Turns one hook event into the session's next state (spec section 4.1).
public enum SessionReducer {
    /// How long after an approval was resolved a `Notification permission_prompt` is treated as
    /// the late echo of that approval, not as a new one.
    public static let lateNotificationWindow: TimeInterval = 10

    public static func reduce(_ current: SessionState?, _ event: HookEvent, context: EventContext) -> ReduceOutcome {
        guard let kind = event.kind else { return .ignore }
        if kind == .sessionEnd { return .delete }
        if kind == .notification, event.notificationType != "permission_prompt", event.notificationType != "idle_prompt" {
            return .ignore
        }

        let now = context.now
        var state = current ?? SessionState(
            sessionId: event.sessionId,
            cwd: event.cwd,
            host: context.host,
            terminalApp: context.terminalApp,
            pid: context.pid,
            now: now
        )
        if !event.cwd.isEmpty { state.cwd = event.cwd }
        state.host = context.host
        state.terminalApp = context.terminalApp
        if let pid = context.pid { state.pid = pid }
        state.lastEvent = now
        if let title = event.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            state.title = title
        }

        // A fresh start ("startup", "clear") has nothing to watch yet; a resumed or compacted session
        // and every other event mean someone works in it.
        if kind != .sessionStart || (event.source != nil && event.source != "startup" && event.source != "clear") {
            state.startedConversation = true
        }

        switch kind {
        case .sessionStart:
            // A new session starts idle (from init); a resumed or compacted one keeps its status.
            break

        case .userPromptSubmit:
            clearApproval(&state, now: now)
            setStatus(&state, .working, now: now)
            state.activity = .thinking
            state.tool = nil
            state.detail = nil

        case .preToolUse:
            state.activity = ActivityClassifier.activity(forTool: event.toolName ?? "", command: event.command)
            if state.status != .needsApproval {
                setStatus(&state, .working, now: now)
                state.tool = event.toolName
                state.detail = ApprovalDetail.describe(event)
            }

        case .postToolUse, .postToolUseFailure:
            if state.status == .needsApproval {
                // Only the call that waited clears the approval: parallel tool calls keep running.
                let matches = state.pendingApproval == nil || state.pendingApproval == ApprovalDetail.signature(event)
                guard matches else { break }
                clearApproval(&state, now: now)
            }
            setStatus(&state, .working, now: now)

        case .permissionRequest:
            state.pendingApproval = ApprovalDetail.signature(event)
            state.tool = event.toolName
            state.detail = ApprovalDetail.describe(event)
            setStatus(&state, .needsApproval, now: now)

        case .notification where event.notificationType == "idle_prompt":
            // Esc mid-turn fires no Stop: Claude waiting for input is the only sign the turn ended.
            // Approvals and reviews keep their orange lamp.
            if state.status == .working {
                state.tool = nil
                state.detail = nil
                setStatus(&state, .idle, now: now)
            }

        case .notification:
            if state.status == .needsApproval { break }
            if let resolved = state.approvalResolvedAt, now.timeIntervalSince(resolved) < lateNotificationWindow { break }
            state.tool = nil
            state.detail = nil
            setStatus(&state, .needsApproval, now: now)

        case .stop:
            clearApproval(&state, now: now)
            state.backgroundTasks = event.runningBackgroundTasks
            state.tool = nil
            state.detail = nil
            setStatus(&state, .awaitingReview, now: now)

        case .subagentStart:
            state.activity = .runningAgents
            if state.status != .needsApproval { setStatus(&state, .working, now: now) }

        case .preCompact:
            state.activity = .compacting
            if state.status != .needsApproval { setStatus(&state, .working, now: now) }

        case .sessionEnd:
            return .delete
        }
        return .write(state)
    }

    private static func setStatus(_ state: inout SessionState, _ status: SessionStatus, now: Date) {
        guard state.status != status else { return }
        state.status = status
        state.statusSince = now
    }

    private static func clearApproval(_ state: inout SessionState, now: Date) {
        if state.status == .needsApproval || state.pendingApproval != nil {
            state.approvalResolvedAt = now
        }
        state.pendingApproval = nil
    }
}
