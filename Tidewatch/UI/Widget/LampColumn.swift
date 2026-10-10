import SwiftUI

@MainActor
struct LampColumn: View {
    let sessions: [DisplayedSession]
    let hoveredIndex: Int?
    let metrics: WidgetMetrics

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                StatusLamp(status: nil)
                    .frame(height: WidgetMetrics.lampPitch)
            } else {
                ForEach(Array(sessions.prefix(WidgetMetrics.maxLamps).enumerated()), id: \.element.id) { index, session in
                    StatusLamp(status: session.status, highlighted: hoveredIndex == index)
                        .frame(height: WidgetMetrics.lampPitch)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            if metrics.hasOverflow {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(GlassColor.textSecondary)
                    .frame(height: WidgetMetrics.chevronHeight)
            }
        }
        .padding(.vertical, WidgetMetrics.columnPadding)
        .frame(width: WidgetMetrics.columnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sessions.count == 1 ? "1 Claude Code session" : "\(sessions.count) Claude Code sessions")
    }
}
