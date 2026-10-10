import SwiftUI

/// `GlassEffectContainer` on macOS 26 (glass shapes morph into each other), plain content below.
struct GlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *), !GlassTokens.forcesFallback {
            GlassEffectContainer(spacing: 2) { content }
        } else {
            content
        }
    }
}
