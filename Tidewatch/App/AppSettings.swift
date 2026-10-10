import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let sounds = "sounds.enabled"
        static let connected = "hooks.connected"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) }
    }

    /// The user connected Tidewatch to Claude Code at least once (repair on launch).
    var hooksConnected: Bool {
        didSet { defaults.set(hooksConnected, forKey: Keys.connected) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundsEnabled = defaults.object(forKey: Keys.sounds) as? Bool ?? true
        hooksConnected = defaults.bool(forKey: Keys.connected)
    }
}
