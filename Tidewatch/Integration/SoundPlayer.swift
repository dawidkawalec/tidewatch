import AppKit

/// Plays a cue when a session starts waiting for approval or finishes its turn (spec 5.5):
/// silent for 3 s after launch, at most one sound per 2 s.
@MainActor
final class SoundPlayer {
    enum Cue: Equatable {
        case approval
        case done

        var soundName: String {
            switch self {
            case .approval: return "Glass"
            case .done: return "Tink"
            }
        }
    }

    static let minimumGap: TimeInterval = 2
    static let launchSilence: TimeInterval = 3

    private let clock: () -> Date
    private let play: (Cue) -> Void
    private let startedAt: Date
    private var lastPlayed: Date?

    init(clock: @escaping () -> Date = { Date() }, play: @escaping (Cue) -> Void = { NSSound(named: NSSound.Name($0.soundName))?.play() }) {
        self.clock = clock
        self.play = play
        startedAt = clock()
    }

    static func cue(for transition: SessionTransition) -> Cue? {
        switch transition.to {
        case .needsApproval: return .approval
        case .awaitingReview: return .done
        case .working, .idle: return nil
        }
    }

    @discardableResult
    func handle(_ transition: SessionTransition, enabled: Bool) -> Bool {
        guard enabled, let cue = Self.cue(for: transition) else { return false }
        let now = clock()
        guard now.timeIntervalSince(startedAt) >= Self.launchSilence else { return false }
        if let lastPlayed, now.timeIntervalSince(lastPlayed) < Self.minimumGap { return false }
        lastPlayed = now
        play(cue)
        return true
    }
}
