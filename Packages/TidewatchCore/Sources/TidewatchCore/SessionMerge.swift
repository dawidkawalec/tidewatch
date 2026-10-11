import Foundation

/// The list of sessions from both sources. The hook files carry the detail (which tool waits for
/// approval, what the agent does); Claude Code's registry knows every open session, also one that
/// fired no hook yet, and the folder it started in.
public enum SessionMerge {
    public static func merge(hooks: [SessionState], processes: [ClaudeProcess]) -> [SessionState] {
        let live = processes.filter { $0.kind == nil || $0.kind == "interactive" }
        let hooksById = Dictionary(hooks.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        let sessionByPid = Dictionary(live.map { ($0.pid, $0.sessionId) }, uniquingKeysWith: { first, _ in first })

        var merged: [SessionState] = []
        for process in live {
            if var state = hooksById[process.sessionId] {
                state.root = process.cwd
                state.pid = process.pid
                state.firstSeen = min(state.firstSeen, process.startedAt)
                merged.append(state)
            } else {
                merged.append(state(from: process))
            }
        }
        let known = Set(live.map(\.sessionId))
        for state in hooks where !known.contains(state.sessionId) {
            // The process now runs another session (after /clear): this file is a leftover.
            if let pid = state.pid, sessionByPid[pid] != nil { continue }
            merged.append(state)
        }
        return merged
    }

    /// A session known only from the registry: its status is coarser than what the hooks report.
    static func state(from process: ClaudeProcess) -> SessionState {
        let host: SessionHost = process.entrypoint == "claude-vscode" ? .vscode : .terminal
        var state = SessionState(sessionId: process.sessionId, cwd: process.cwd, host: host, terminalApp: nil, pid: process.pid, now: process.startedAt)
        state.startedConversation = nil
        switch process.status {
        case "busy": state.status = .working
        case "waiting": state.status = .needsApproval
        default: state.status = .idle
        }
        state.statusSince = process.statusUpdatedAt ?? process.startedAt
        state.lastEvent = process.updatedAt ?? process.startedAt
        return state
    }
}
