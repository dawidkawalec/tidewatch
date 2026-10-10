import SwiftUI

/// The widget's glass (column and panel), from Captylo's RecorderGlass + GlassSurface, trimmed.
/// macOS 26: regular Liquid Glass with a light tint and `glassEffectID`, so the column and the
/// panel morph inside `GlassContainer`. macOS 14/15: material + white fill + smoke + rim.
/// Reduce Transparency: solid fill with the same rim.
@MainActor
struct WidgetGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { shape.fill(GlassColor.solidPanel) }
                .overlay { rim }
        } else if #available(macOS 26.0, *), !GlassTokens.forcesFallback {
            content
                .clipShape(shape)
                .background {
                    shape.fill(BrandColor.abyss.opacity(GlassTokens.Widget.smoke))
                        .overlay { shape.fill(Color.white.opacity(GlassTokens.Widget.wash)) }
                        .allowsHitTesting(false)
                }
                .glassEffect(Glass.regular.tint(Color.black.opacity(GlassTokens.Widget.tint)), in: shape)
                .glassEffectID(id, in: namespace)
                .overlay { rim }
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(Color.white.opacity(GlassTokens.Opacity.fallbackFill)) }
                        .overlay { shape.fill(BrandColor.abyss.opacity(GlassTokens.Widget.smoke)) }
                        .shadow(color: .black.opacity(GlassTokens.Opacity.shadow), radius: GlassTokens.Shadow.panelRadius, y: GlassTokens.Shadow.panelY)
                }
                .overlay { rim }
        }
    }

    private var rim: some View {
        shape
            .strokeBorder(GlassColor.rim(top: 0.6, bottom: 0.2), lineWidth: GlassTokens.Size.rimWidth)
            .allowsHitTesting(false)
    }
}

extension View {
    func widgetGlass<S: InsettableShape>(_ id: String, in shape: S, namespace: Namespace.ID) -> some View {
        modifier(WidgetGlass(shape: shape, id: id, namespace: namespace))
    }
}
