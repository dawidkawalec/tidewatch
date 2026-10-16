import SwiftUI

// Glass tokens: the type and radii of Captylo's Dusk Glass on a light, blurred glass
// (`WidgetGlass`). The widget follows the system appearance unless the user picks one: light
// glass with dark type, dark glass with light type. Views never hard-code radii, opacities,
// colours or fonts.

enum GlassTokens {
    enum Radius {
        static let panel: CGFloat = 28
        static let row: CGFloat = 12
    }

    enum Size {
        static let rimWidth: CGFloat = 1
    }

    enum Opacity {
        /// Badge fill inside the panel (scaled by `GlassColor.fill`).
        static let control: Double = 0.14
        /// Hovered row.
        static let rowHover: Double = 0.08
    }

    enum Shadow {
        /// Hairline around the glass: dark in light mode, light in dark mode.
        static let hairline: Double = 0.08
        /// Heavier shadow of the macOS 14/15 material path.
        static let fallbackOpacity: Double = 0.22
        static let fallbackRadius: CGFloat = 24
        static let fallbackY: CGFloat = 10
    }

    /// The widget's light glass (`WidgetGlass`, `WindowBlur`): the background shows through it.
    /// The blur radius and the tint density are the user's (`AppSettings.GlassBlur`, `GlassTint`).
    enum Liquid {
        /// White sheen fading from the top edge to the middle.
        static let sheen: Double = 0.16
        /// "Text contrast" halo under the widget's text.
        static let haloOpacity: Double = 0.75
        static let haloRadius: CGFloat = 1.5
    }
}

enum GlassColor {
    /// Adaptive label styles: vibrant on Liquid Glass, dark in light mode, light in dark mode.
    static let textPrimary = AnyShapeStyle(.primary)
    static let textSecondary = AnyShapeStyle(.secondary)
    static let textTertiary = AnyShapeStyle(.tertiary)
    /// Badge and hovered-row fills inside the panel.
    static func fill(_ opacity: Double) -> Color {
        Color.primary.opacity(opacity * 0.55)
    }
    /// Working lamp (Captylo's success green).
    static let success = Color(hex: 0x4CD68A)
    /// Needs approval / awaiting review lamp and text (the mockups' orange).
    static let attention = Color(hex: 0xFF9F43)
    /// Status text in the attention colour: a deeper orange on light glass, so it keeps contrast
    /// over warm wallpapers seen through the clear glass.
    static let attentionText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.62, blue: 0.26, alpha: 1)
            : NSColor(srgbRed: 0.68, green: 0.29, blue: 0.0, alpha: 1)
    })
    static let idleLamp = Color(hex: 0x9AA3AD)
    /// The VS Code glyph in the rows.
    static let vscode = Color(hex: 0x3BA0F0)

    /// Rim stroke of the macOS 14/15 path: luminous top edge fading toward the bottom.
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
    /// iOS-like Liquid Glass motion: a little overshoot, settles fast.
    static var liquid: Animation { .spring(response: 0.46, dampingFraction: 0.72) }
    static var reduced: Animation { .easeInOut(duration: 0.18) }
}
