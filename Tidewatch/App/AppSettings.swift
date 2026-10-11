import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let sounds = "sounds.enabled"
        static let connected = "hooks.connected"
        static let blur = "glass.blurRadius"
        static let tint = "glass.tintOpacity"
        static let appearance = "glass.appearance"
        static let contrast = "glass.textContrast"
        static let reviewFade = "review.fade"
    }

    /// Blur behind the glass, in points (`WindowBlur`).
    static let blurRange: ClosedRange<Double> = 0...20
    /// Opacity of the glass's tint (white in light, black in dark).
    static let tintRange: ClosedRange<Double> = 0...0.6
    static let defaultBlur: Double = 8
    static let defaultTint: Double = 0.25

    /// Light or dark glass; `system` follows macOS. Dark glass reads well over dark pages on a light
    /// system, and the other way round.
    enum GlassAppearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
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
            case .fiveMinutes: return "After 5 minutes"
            case .tenMinutes: return "After 10 minutes"
            case .thirtyMinutes: return "After 30 minutes"
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

    var glassBlur: Double {
        didSet {
            let clamped = glassBlur.clamped(to: Self.blurRange)
            if clamped != glassBlur { glassBlur = clamped; return }
            defaults.set(glassBlur, forKey: Keys.blur)
        }
    }

    var glassTint: Double {
        didSet {
            let clamped = glassTint.clamped(to: Self.tintRange)
            if clamped != glassTint { glassTint = clamped; return }
            defaults.set(glassTint, forKey: Keys.tint)
        }
    }

    var glassAppearance: GlassAppearance {
        didSet { defaults.set(glassAppearance.rawValue, forKey: Keys.appearance) }
    }

    /// A soft halo under the widget's text, so it reads over any background.
    var textContrast: Bool {
        didSet { defaults.set(textContrast, forKey: Keys.contrast) }
    }

    var reviewFade: ReviewFade {
        didSet { defaults.set(reviewFade.rawValue, forKey: Keys.reviewFade) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundsEnabled = defaults.object(forKey: Keys.sounds) as? Bool ?? true
        hooksConnected = defaults.bool(forKey: Keys.connected)
        glassBlur = (defaults.object(forKey: Keys.blur) as? Double ?? Self.defaultBlur).clamped(to: Self.blurRange)
        glassTint = (defaults.object(forKey: Keys.tint) as? Double ?? Self.defaultTint).clamped(to: Self.tintRange)
        glassAppearance = defaults.string(forKey: Keys.appearance).flatMap(GlassAppearance.init(rawValue:)) ?? .system
        textContrast = defaults.object(forKey: Keys.contrast) as? Bool ?? true
        reviewFade = defaults.string(forKey: Keys.reviewFade).flatMap(ReviewFade.init(rawValue:)) ?? .tenMinutes
    }

    /// "Reset to Defaults" in the settings window (the glass only).
    func resetGlass() {
        glassBlur = Self.defaultBlur
        glassTint = Self.defaultTint
        glassAppearance = .system
        textContrast = true
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
