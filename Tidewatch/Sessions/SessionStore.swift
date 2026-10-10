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

/// A shown status that changed between two reloads (sounds).
struct SessionTransition: Equatable, Sendable {
    let sessionId: String
    let from: SessionStatus?
    let to: SessionStatus
}

/// The sessions folder as the widget sees it: loads the files, drops ended sessions, applies the
/// display rules and reports status changes. Reloads on folder changes and every 15 s (time rules,
/// liveness).
@MainActor
@Observable
final class SessionStore {
    static let refreshInterval: Duration = .seconds(15)

    private(set) var sessions: [DisplayedSession] = []
    @ObservationIgnored var onTransition: ((SessionTransition) -> Void)?
    @ObservationIgnored let fileStore: SessionFileStore
    @ObservationIgnored private let acknowledged: AcknowledgedStore
    @ObservationIgnored private let isAlive: @Sendable (Int32) -> Bool
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var watcher: SessionFolderWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastStatuses: [String: SessionStatus] = [:]
    @ObservationIgnored private var hasLoaded = false

    init(
        fileStore: SessionFileStore,
        acknowledged: AcknowledgedStore,
        isAlive: @escaping @Sendable (Int32) -> Bool = ProcessLiveness.isAlive,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileStore = fileStore
        self.acknowledged = acknowledged
        self.isAlive = isAlive
        self.clock = clock
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
        var live: [SessionState] = []
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
            live.append(state)
        }

        let ordered = DisplayRules.ordered(live)
        let names = DisplayRules.names(for: ordered)
        let displayed = ordered.map { state in
            DisplayedSession(
                state: state,
                status: DisplayRules.displayStatus(state, now: now, acknowledgedAt: acknowledged.acknowledgedAt(state.sessionId)),
                name: names[state.sessionId] ?? state.project
            )
        }

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
        if displayed != sessions { sessions = displayed }
    }

    /// The user opened this session from the widget.
    func acknowledge(_ session: DisplayedSession) {
        acknowledged.set(session.state.lastEvent, for: session.id)
        reload()
    }
}
