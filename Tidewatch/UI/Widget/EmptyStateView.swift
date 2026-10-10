import SwiftUI

@MainActor
struct EmptyStateView: View {
    let isConnected: Bool
    let connect: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isConnected {
                Text("No sessions yet")
                    .font(GlassFont.rowTitle)
                    .foregroundStyle(GlassColor.textSecondary)
                Text("Start Claude Code and it shows up here.")
                    .font(GlassFont.rowSubtitle)
                    .foregroundStyle(GlassColor.textTertiary)
            } else {
                Text("Not connected to Claude Code")
                    .font(GlassFont.rowTitle)
                    .foregroundStyle(GlassColor.textSecondary)
                Button("Connect to Claude Code") { connect() }
                    .buttonStyle(.plain)
                    .font(GlassFont.button)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background { Capsule().fill(BrandColor.tide.opacity(0.85)) }
                    .overlay { Capsule().strokeBorder(GlassColor.rim(top: 0.4, bottom: 0.1), lineWidth: GlassTokens.Size.rimWidth) }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
