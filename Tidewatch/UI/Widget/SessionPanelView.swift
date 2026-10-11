import SwiftUI

/// The expanded panel (mockups: "AI Agents" + count, one row per session). A VS Code window with
/// several tabs gets a header with its folder name above its rows.
@MainActor
struct SessionPanelView: View {
    let groups: [SessionGroup]
    let hoveredIndex: Int?
    let isConnected: Bool
    let metrics: WidgetMetrics
    let actions: WidgetActions

    private var sessions: [DisplayedSession] { groups.flatMap(\.sessions) }

    var body: some View {
        let sessions = sessions
        VStack(spacing: 0) {
            header
                .frame(height: WidgetMetrics.headerHeight)
                .contentShape(Rectangle())
                .contextMenu { WidgetMenu(actions: actions) }
            if sessions.isEmpty {
                EmptyStateView(isConnected: isConnected, connect: actions.connect)
                    .frame(height: WidgetMetrics.emptyStateHeight)
            } else {
                let windows = Dictionary(uniqueKeysWithValues: groups.compactMap { group in
                    group.sessions.first.map { ($0.id, group) }
                })
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                                if metrics.headerBefore(index), let window = windows[session.id] {
                                    WindowHeader(name: window.name, count: window.sessions.count)
                                        .frame(height: WidgetMetrics.groupHeaderHeight)
                                }
                                SessionRow(session: session, now: context.date, highlighted: hoveredIndex == index, actions: actions)
                                    .frame(height: WidgetMetrics.rowHeight)
                            }
                        }
                    }
                    .scrollDisabled(!metrics.scrolls)
                    .scrollIndicators(.never)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, WidgetMetrics.panelBottomPadding)
    }

    private var header: some View {
        HStack {
            Text("AI Agents")
                .font(GlassFont.sectionTitle)
                .foregroundStyle(GlassColor.textPrimary)
            Spacer()
            Button {
                actions.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GlassColor.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            Text("\(sessions.count)")
                .font(GlassFont.badge)
                .foregroundStyle(GlassColor.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background { Capsule().fill(GlassColor.fill(GlassTokens.Opacity.control)) }
                .overlay { Capsule().strokeBorder(GlassColor.rim(top: 0.32, bottom: 0.06), lineWidth: GlassTokens.Size.rimWidth) }
        }
        .padding(.horizontal, 12)
    }
}

/// A VS Code window above its tabs.
@MainActor
struct WindowHeader: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "macwindow")
                .font(.system(size: 10, weight: .semibold))
            Text(name)
                .font(GlassFont.rowSubtitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(count) tabs")
                .font(GlassFont.rowSubtitle)
        }
        .foregroundStyle(GlassColor.textSecondary)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) window, \(count) tabs")
    }
}
