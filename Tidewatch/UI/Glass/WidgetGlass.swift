import SwiftUI

/// The widget's glass (column and panel): a light tinted fill that follows the system appearance,
/// a sheen on the upper half, a luminous rim and a soft shadow under the shape only. The blur
/// behind it comes from the window (`WindowBlur`, a small radius, so the background still shows
/// through). Reduce Transparency: solid window background with the same rim.
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
                        .shadow(color: .black.opacity(GlassTokens.Shadow.liftOpacity), radius: GlassTokens.Shadow.liftRadius, y: GlassTokens.Shadow.liftY)
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

extension View {
    func widgetGlass<S: InsettableShape>(in shape: S, tint: Double) -> some View {
        modifier(WidgetGlass(shape: shape, tint: tint))
    }
}
