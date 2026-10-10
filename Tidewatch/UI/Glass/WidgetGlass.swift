import SwiftUI

/// The widget's glass (column and panel). macOS 26: native Liquid Glass with `glassEffectID`, so
/// the column and the panel morph inside `GlassContainer`; it refracts what is behind it and
/// follows the system appearance. A soft lift shadow keeps clear glass visible over white
/// documents. macOS 14/15: regular material + rim + shadow. Reduce Transparency: solid window
/// background with the same rim.
@MainActor
struct WidgetGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { shape.fill(Color(nsColor: .windowBackgroundColor)) }
                .overlay { rim }
        } else if #available(macOS 26.0, *), !GlassTokens.forcesFallback {
            content
                .clipShape(shape)
                // Interactive: the glass reacts to the pointer like iOS controls.
                .glassEffect(Glass.regular.tint(Color.black.opacity(GlassTokens.Liquid.dim)).interactive(), in: shape)
                .glassEffectID(id, in: namespace)
                .overlay {
                    shape
                        .strokeBorder(Color.primary.opacity(GlassTokens.Shadow.hairline), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(GlassTokens.Shadow.liftOpacity), radius: GlassTokens.Shadow.liftRadius, y: GlassTokens.Shadow.liftY)
        } else {
            content
                .background {
                    shape.fill(.regularMaterial)
                        .shadow(color: .black.opacity(GlassTokens.Shadow.fallbackOpacity), radius: GlassTokens.Shadow.fallbackRadius, y: GlassTokens.Shadow.fallbackY)
                }
                .overlay { rim }
        }
    }

    private var rim: some View {
        shape
            .strokeBorder(GlassColor.rim(top: colorScheme == .dark ? 0.6 : 0.9, bottom: 0.2), lineWidth: GlassTokens.Size.rimWidth)
            .allowsHitTesting(false)
    }
}

extension View {
    func widgetGlass<S: InsettableShape>(_ id: String, in shape: S, namespace: Namespace.ID) -> some View {
        modifier(WidgetGlass(shape: shape, id: id, namespace: namespace))
    }
}
