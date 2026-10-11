import Foundation
import Observation
import TidewatchCore

/// A session as the widget shows it right now.
struct DisplayedSession: Identifiable, Equatable, Sendable {
    let state: SessionState
    let status: SessionStatus
    let name: String
    var id: String { state.sessionId }
}

/// One VS Code window (or one terminal session) and its sessions, in stable order.
struct SessionGroup: Identifiable, Equatable, Sendable {
    let id: String
    /// The window's folder name.
    let name: String
    let sessions: [DisplayedSession]
}

/// A shown status that changed between two reloads (sounds).
struct SessionTransition: Equatable, Sendable {
    let sessionId: String
    let from: SessionStatus?
    let to: SessionStatus
}

/// The sessions as the widget sees them: loads the hook files, drops ended sessions, adds the open
/// sessions Claude Code lists that fired no hook yet, applies the display rules, groups them by
/// window and reports status changes. Reloads on folder changes and every 15 s (time rules,
/// liveness, the registry).
@MainActor
@Observable
final class SessionStore {
    static let refreshInterval: Duration = .seconds(15)

    private(set) var groups: [SessionGroup] = []
    /// All sessions in widget order (lamp and row indexes).
    private(set) var sessions: [DisplayedSession] = []
    @ObservationIgnored var onTransition: ((SessionTransition) -> Void)?
    @ObservationIgnored let fileStore: SessionFileStore
    @ObservationIgnored private let acknowledged: AcknowledgedStore
    @ObservationIgnored private let isAlive: @Sendable (Int32) -> Bool
    @ObservationIgnored private let clock: @Sendable () -> Date
    /// The user's home folder, for `DisplayRules.isShown` (Claude Code's own `~/.claude`).
    @ObservationIgnored private let home: String
    @ObservationIgnored private let system: ClaudeSystem
    /// The user's "Awaiting review" fade time (nil = never).
    @ObservationIgnored private let reviewFade: () -> TimeInterval?
    @ObservationIgnored private var watcher: SessionFolderWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastStatuses: [String: SessionStatus] = [:]
    @ObservationIgnored private var hasLoaded = false

    init(
        fileStore: SessionFileStore,
        acknowledged: AcknowledgedStore,
        isAlive: @escaping @Sendable (Int32) -> Bool = ProcessLiveness.isAlive,
        clock: @escaping @Sendable () -> Date = { Date() },
        home: String = NSHomeDirectory(),
        system: ClaudeSystem = .none,
        reviewFade: @escaping () -> TimeInterval? = { DisplayRules.reviewToIdle }
    ) {
        self.reviewFade = reviewFade
        self.fileStore = fileStore
        self.acknowledged = acknowledged
        self.isAlive = isAlive
        self.clock = clock
        self.home = home
        self.system = system
    }

    func start() {
        try? FileManager.default.createDirectory(at: fileStore.directory, withIntermediateDirectories: true)
        reload()
        watcher = SessionFolderWatcher(directory: fileStore.directory) { [weak self] in
            self?.reload()
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                self?.reload()
            }
        }
    }

    func reload() {
        let now = clock()
        var hooks: [SessionState] = []
        for state in fileStore.loadAll() {
            // A live process keeps its session (an idle tab overnight stays put); the 6 h rule is
            // only the fallback for sessions without a pid (spec 4.2).
            let ended = state.pid.map { !isAlive($0) || DisplayRules.isAbandoned(state, now: now) }
                ?? DisplayRules.isStale(state, now: now)
            if ended {
                fileStore.remove(sessionId: state.sessionId)
                Log.sessions.info("dropped an ended session")
                continue
            }
            hooks.append(state)
        }

        var live: [SessionState] = []
        for var state in SessionMerge.merge(hooks: hooks, processes: system.processes()) {
            let transcript = system.transcript(state)
            // Empty tabs and Claude Code's helpers keep their files but get no lamp.
            guard DisplayRules.isShown(state, home: home, hasTranscript: transcript.exists) else { continue }
            if let title = transcript.title { state.title = title }
            live.append(state)
        }

        // A VS Code tab's process is a child of its window's extension host.
        let parent = system.parent
        func windowKey(_ state: SessionState) -> String {
            state.pid.flatMap(parent).map { "window-\($0)" } ?? "session-\(state.sessionId)"
        }
        let grouped = DisplayRules.grouped(live, window: windowKey)
        let names = DisplayRules.names(for: grouped)
        let fade = reviewFade()
        let nextGroups = grouped.map { members in
            SessionGroup(
                id: members.first.map(windowKey) ?? "",
                name: members.first?.project ?? "",
                sessions: members.map { state in
                    DisplayedSession(
                        state: state,
                        status: DisplayRules.displayStatus(state, now: now, acknowledgedAt: acknowledged.acknowledgedAt(state.sessionId), reviewFade: fade),
                        name: names[state.sessionId] ?? state.project
                    )
                }
            )
        }
        let displayed = nextGroups.flatMap(\.sessions)

        var statuses: [String: SessionStatus] = [:]
        for session in displayed {
            statuses[session.id] = session.status
            if hasLoaded, lastStatuses[session.id] != session.status {
                onTransition?(SessionTransition(sessionId: session.id, from: lastStatuses[session.id], to: session.status))
            }
        }
        lastStatuses = statuses
        hasLoaded = true
        acknowledged.prune(keeping: Set(statuses.keys))
        if nextGroups != groups { groups = nextGroups }
        if displayed != sessions { sessions = displayed }
    }

    /// The user opened this session from the widget.
    func acknowledge(_ session: DisplayedSession) {
        acknowledged.set(session.state.lastEvent, for: session.id)
        reload()
    }
}
