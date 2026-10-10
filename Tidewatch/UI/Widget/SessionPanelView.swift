import SwiftUI

/// The expanded panel (mockups: "AI Agents" + count, one row per session).
@MainActor
struct SessionPanelView: View {
    let sessions: [DisplayedSession]
    let hoveredIndex: Int?
    let isConnected: Bool
    let actions: WidgetActions

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: WidgetMetrics.headerHeight)
            if sessions.isEmpty {
                EmptyStateView(isConnected: isConnected, connect: actions.connect)
                    .frame(height: WidgetMetrics.emptyStateHeight)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session, now: context.date, highlighted: hoveredIndex == index, actions: actions)
                                    .frame(height: WidgetMetrics.rowHeight)
                            }
                        }
                    }
                    .scrollDisabled(sessions.count <= WidgetMetrics.maxVisibleRows)
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
            Text("\(sessions.count)")
                .font(GlassFont.badge)
                .foregroundStyle(GlassColor.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background { Capsule().fill(Color.white.opacity(GlassTokens.Opacity.control)) }
                .overlay { Capsule().strokeBorder(GlassColor.rim(top: 0.32, bottom: 0.06), lineWidth: GlassTokens.Size.rimWidth) }
        }
        .padding(.horizontal, 12)
    }
}
