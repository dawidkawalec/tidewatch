import SwiftUI

// Dusk Glass tokens, trimmed from Captylo's GlassTokens.swift (<captylo-repo>,
// docs/design/dusk-glass.md). Views never hard-code radii, opacities, colours or fonts.

enum GlassTokens {
    enum Radius {
        static let panel: CGFloat = 28
        static let row: CGFloat = 12
    }

    enum Size {
        static let rimWidth: CGFloat = 1
    }

    enum Opacity {
        /// White fill over the material on the macOS 14/15 path.
        static let fallbackFill: Double = 0.12
        /// Badge and button fills inside the panel.
        static let control: Double = 0.14
        /// Hovered row.
        static let rowHover: Double = 0.08
        static let shadow: Double = 0.28
    }

    enum Shadow {
        static let panelRadius: CGFloat = 30
        static let panelY: CGFloat = 14
    }

    /// The widget's glass, tuned against docs/design mockups (dark smoked glass, white type) and
    /// over white documents, where lighter values turned the glass pale and the type unreadable.
    enum Widget {
        /// White wash inside the glass.
        static let wash: Double = 0.05
        /// Abyss smoke inside the glass.
        static let smoke: Double = 0.75
        /// Black tint of macOS 26 regular glass.
        static let tint: Double = 0.20
    }

    /// `TIDEWATCH_GLASS_FALLBACK=1` draws the macOS 14/15 material path on macOS 26 (to check it).
    static let forcesFallback: Bool = ProcessInfo.processInfo.environment["TIDEWATCH_GLASS_FALLBACK"] == "1"
}

enum GlassColor {
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.50)
    static let separator = Color.white.opacity(0.12)
    /// Working lamp (Captylo's success green).
    static let success = Color(hex: 0x4CD68A)
    /// Needs approval / awaiting review lamp and text (new in Tidewatch, the mockups' orange).
    static let attention = Color(hex: 0xFF9F43)
    static let idleLamp = Color.white.opacity(0.35)
    /// The VS Code glyph in the rows.
    static let vscode = Color(hex: 0x3BA0F0)
    /// Reduce Transparency fill.
    static let solidPanel = Color(hex: 0x1C3A40)

    /// Rim stroke: luminous top edge fading toward the bottom.
    static func rim(top: Double = 0.62, bottom: Double = 0.14) -> LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(top), Color.white.opacity(bottom), Color.white.opacity(bottom * 1.6)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Manrope for titles and numbers, Inter for UI (bundled, SIL OFL, `ATSApplicationFontsPath`).
enum GlassFont {
    enum Face: String {
        case manropeSemiBold = "Manrope-SemiBold"
        case manropeBold = "Manrope-Bold"
        case interRegular = "Inter-Regular"
        case interMedium = "Inter-Medium"
        case interSemiBold = "Inter-SemiBold"
    }

    static func face(_ face: Face, _ size: CGFloat) -> Font {
        .custom(face.rawValue, fixedSize: size)
    }

    static var sectionTitle: Font { face(.manropeSemiBold, 15) }
    static var rowTitle: Font { face(.interMedium, 14) }
    static var rowSubtitle: Font { face(.interRegular, 12) }
    static var rowValue: Font { face(.interRegular, 13).monospacedDigit() }
    static var badge: Font { face(.interSemiBold, 11).monospacedDigit() }
    static var button: Font { face(.interSemiBold, 13) }
}

enum GlassMotion {
    static var spring: Animation { .spring(response: 0.38, dampingFraction: 0.85) }
    static var reduced: Animation { .easeInOut(duration: 0.18) }
}
