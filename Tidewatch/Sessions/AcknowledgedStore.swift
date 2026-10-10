import Foundation

/// Sessions the user opened from Tidewatch, with the `lastEvent` they had at that moment: an
/// "Awaiting review" session shows idle until its next event. Kept in UserDefaults, so the app
/// never writes the helper's session files. Stored as reference-date seconds (exact Double).
@MainActor
final class AcknowledgedStore {
    private static let key = "sessions.acknowledged"
    private let defaults: UserDefaults
    private var values: [String: Double]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
    }

    func acknowledgedAt(_ sessionId: String) -> Date? {
        values[sessionId].map(Date.init(timeIntervalSinceReferenceDate:))
    }

    func set(_ date: Date, for sessionId: String) {
        values[sessionId] = date.timeIntervalSinceReferenceDate
        defaults.set(values, forKey: Self.key)
    }

    func prune(keeping ids: Set<String>) {
        let kept = values.filter { ids.contains($0.key) }
        guard kept.count != values.count else { return }
        values = kept
        defaults.set(values, forKey: Self.key)
    }
}
