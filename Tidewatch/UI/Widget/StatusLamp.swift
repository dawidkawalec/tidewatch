import SwiftUI
import TidewatchCore

/// One glass status lamp. Working lamps pulse softly (off with Reduce Motion).
@MainActor
struct StatusLamp: View {
    let status: SessionStatus?
    var highlighted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = StatusPalette.lamp(status)
        Circle()
            .fill(color)
            .frame(width: WidgetMetrics.lampSize, height: WidgetMetrics.lampSize)
            .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
            .shadow(color: StatusPalette.glows(status) ? color.opacity(0.75) : .clear, radius: highlighted ? 6 : 4)
            .background {
                if status == .working, !reduceMotion {
                    PhaseAnimator([false, true]) { grown in
                        Circle()
                            .fill(color.opacity(grown ? 0 : 0.45))
                            .frame(width: WidgetMetrics.lampSize, height: WidgetMetrics.lampSize)
                            .scaleEffect(grown ? 2.2 : 1)
                    } animation: { grown in
                        grown ? .easeOut(duration: 1.8) : nil
                    }
                }
            }
            .scaleEffect(highlighted ? 1.25 : 1)
            .animation(reduceMotion ? nil : GlassMotion.spring, value: highlighted)
    }
}
