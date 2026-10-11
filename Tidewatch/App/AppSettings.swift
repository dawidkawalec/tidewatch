import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let sounds = "sounds.enabled"
        static let connected = "hooks.connected"
        static let blur = "glass.blur"
        static let tint = "glass.tint"
        static let reviewFade = "review.fade"
    }

    /// How much the glass blurs what is behind it.
    enum GlassBlur: String, CaseIterable, Identifiable {
        case light, medium, strong
        var id: String { rawValue }
        var radius: Int {
            switch self {
            case .light: return 4
            case .medium: return 8
            case .strong: return 14
            }
        }
        var label: String { rawValue.capitalized }
    }

    /// How dense the glass's tint is (white in light mode, black in dark mode).
    enum GlassTint: String, CaseIterable, Identifiable {
        case lighter, standard, darker
        var id: String { rawValue }
        var fill: Double {
            switch self {
            case .lighter: return 0.15
            case .standard: return 0.25
            case .darker: return 0.38
            }
        }
        var label: String {
            switch self {
            case .lighter: return "Lighter"
            case .standard: return "Default"
            case .darker: return "Denser"
            }
        }
    }

    /// When "Awaiting review" fades to "Idle" on its own.
    enum ReviewFade: String, CaseIterable, Identifiable {
        case fiveMinutes, tenMinutes, thirtyMinutes, never
        var id: String { rawValue }
        var seconds: TimeInterval? {
            switch self {
            case .fiveMinutes: return 5 * 60
            case .tenMinutes: return 10 * 60
            case .thirtyMinutes: return 30 * 60
            case .never: return nil
            }
        }
        var label: String {
            switch self {
            case .fiveMinutes: return "After 5 Minutes"
            case .tenMinutes: return "After 10 Minutes"
            case .thirtyMinutes: return "After 30 Minutes"
            case .never: return "Never (until opened)"
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) }
    }

    /// The user connected Tidewatch to Claude Code at least once (repair on launch).
    var hooksConnected: Bool {
        didSet { defaults.set(hooksConnected, forKey: Keys.connected) }
    }

    var glassBlur: GlassBlur {
        didSet { defaults.set(glassBlur.rawValue, forKey: Keys.blur) }
    }

    var glassTint: GlassTint {
        didSet { defaults.set(glassTint.rawValue, forKey: Keys.tint) }
    }

    var reviewFade: ReviewFade {
        didSet { defaults.set(reviewFade.rawValue, forKey: Keys.reviewFade) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundsEnabled = defaults.object(forKey: Keys.sounds) as? Bool ?? true
        hooksConnected = defaults.bool(forKey: Keys.connected)
        glassBlur = defaults.string(forKey: Keys.blur).flatMap(GlassBlur.init(rawValue:)) ?? .medium
        glassTint = defaults.string(forKey: Keys.tint).flatMap(GlassTint.init(rawValue:)) ?? .standard
        reviewFade = defaults.string(forKey: Keys.reviewFade).flatMap(ReviewFade.init(rawValue:)) ?? .tenMinutes
    }
}
