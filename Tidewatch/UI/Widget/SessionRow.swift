import SwiftUI
import TidewatchCore

@MainActor
struct SessionRow: View {
    let session: DisplayedSession
    let now: Date
    let highlighted: Bool
    let actions: WidgetActions

    var body: some View {
        let statusLine = DisplayRules.statusLine(session.state, status: session.status)
        Button {
            actions.open(session)
        } label: {
            HStack(spacing: 12) {
                StatusLamp(status: session.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(GlassFont.rowTitle)
                        .foregroundStyle(GlassColor.textPrimary)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(GlassFont.rowSubtitle)
                        .foregroundStyle(StatusPalette.text(session.status))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Text(DisplayRules.elapsed(since: session.state.statusSince, now: now))
                    .font(GlassFont.rowValue)
                    .foregroundStyle(GlassColor.textTertiary)
                Image(systemName: session.state.host == .vscode ? "chevron.left.forwardslash.chevron.right" : "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(session.state.host == .vscode ? GlassColor.vscode : GlassColor.textSecondary)
                    .frame(width: 18)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: GlassTokens.Radius.row, style: .continuous)
                    .fill(Color.white.opacity(highlighted ? GlassTokens.Opacity.rowHover : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show in Finder") { actions.showInFinder(session) }
        }
        .accessibilityLabel("\(session.name), \(statusLine)")
    }
}
