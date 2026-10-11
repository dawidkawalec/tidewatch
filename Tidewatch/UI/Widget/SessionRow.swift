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
        let project = DisplayRules.projectSuffix(session.state, name: session.name)
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
                    HStack(spacing: 0) {
                        // What happens matters more than the project: the status takes its room
                        // first, the project gives way and keeps at least its beginning.
                        Text(statusLine)
                            .foregroundStyle(StatusPalette.text(session.status))
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        if let project {
                            Text(" · \(project)")
                                .foregroundStyle(GlassColor.textSecondary)
                                .truncationMode(.tail)
                                .frame(minWidth: 44, alignment: .leading)
                        }
                    }
                    .font(GlassFont.rowSubtitle)
                    .lineLimit(1)
                }
                // The text takes all the room the time and the icon leave.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                Text(DisplayRules.elapsed(since: session.state.statusSince, now: now))
                    .font(GlassFont.rowValue)
                    .foregroundStyle(GlassColor.textTertiary)
                Image(systemName: session.state.host == .vscode ? "chevron.left.forwardslash.chevron.right" : "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(session.state.host == .vscode ? AnyShapeStyle(GlassColor.vscode) : GlassColor.textSecondary)
                    .frame(width: 18)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: GlassTokens.Radius.row, style: .continuous)
                    .fill(GlassColor.fill(highlighted ? GlassTokens.Opacity.rowHover : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show in Finder") { actions.showInFinder(session) }
            Divider()
            WidgetMenu(actions: actions)
        }
        .accessibilityLabel([session.name, statusLine, project].compactMap { $0 }.joined(separator: ", "))
    }
}
