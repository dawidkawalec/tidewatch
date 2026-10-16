import SwiftUI

/// The widget's glass (column and panel): a light tinted fill that follows the system appearance,
/// a sheen on the upper half and a luminous rim. The blur behind it comes from the window
/// (`WindowBlur`, a small radius, so the background still shows through). No drop shadow: the
/// window server blurs behind every visible pixel, so a soft shadow showed as a blurred halo around
/// the glass (owner, 2026-10-16). Reduce Transparency: solid window background with the same rim.
@MainActor
struct WidgetGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    /// Opacity of the tint (`AppSettings.GlassTint`).
    let tint: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { shape.fill(Color(nsColor: .windowBackgroundColor)) }
                .overlay { rim }
        } else {
            content
                .background {
                    shape.fill(fill)
                        .overlay {
                            shape.fill(LinearGradient(colors: [Color.white.opacity(GlassTokens.Liquid.sheen), .clear], startPoint: .top, endPoint: .center))
                        }
                        .allowsHitTesting(false)
                }
                .overlay { rim }
        }
    }

    private var fill: Color {
        colorScheme == .dark
            ? Color.black.opacity(tint)
            : Color.white.opacity(tint)
    }

    private var rim: some View {
        shape
            .strokeBorder(GlassColor.rim(top: colorScheme == .dark ? 0.6 : 0.9, bottom: 0.2), lineWidth: GlassTokens.Size.rimWidth)
            .allowsHitTesting(false)
    }
}

/// "Text contrast": a soft halo in the opposite tone under the text, so it reads over any
/// background behind the light glass.
@MainActor
struct TextHalo: ViewModifier {
    let enabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(color: enabled ? (colorScheme == .dark ? Color.black : Color.white).opacity(GlassTokens.Liquid.haloOpacity) : .clear, radius: GlassTokens.Liquid.haloRadius)
    }
}

extension View {
    func textHalo(_ enabled: Bool) -> some View {
        modifier(TextHalo(enabled: enabled))
    }

    func widgetGlass<S: InsettableShape>(in shape: S, tint: Double) -> some View {
        modifier(WidgetGlass(shape: shape, tint: tint))
    }
}
