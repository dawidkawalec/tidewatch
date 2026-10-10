import SwiftUI
import TidewatchCore

/// One status lamp, drawn as a small glass gem: a lit core, a soft shadow toward the bottom and a
/// specular highlight. Working lamps pulse softly (off with Reduce Motion).
@MainActor
struct StatusLamp: View {
    let status: SessionStatus?
    var highlighted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = StatusPalette.lamp(status)
        let size = WidgetMetrics.lampSize
        gem(color, size: size)
            .frame(width: size, height: size)
            .shadow(color: StatusPalette.glows(status) ? color.opacity(0.75) : .clear, radius: highlighted ? 6 : 4)
            .background {
                if status == .working, !reduceMotion {
                    PhaseAnimator([false, true]) { grown in
                        Circle()
                            .fill(color.opacity(grown ? 0 : 0.45))
                            .frame(width: size, height: size)
                            .scaleEffect(grown ? 2.2 : 1)
                    } animation: { grown in
                        grown ? .easeOut(duration: 1.8) : nil
                    }
                }
            }
            .scaleEffect(highlighted ? 1.25 : 1)
            .animation(reduceMotion ? nil : GlassMotion.spring, value: highlighted)
    }

    private func gem(_ color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(color)
            // Lit from the top left, darker toward the bottom right.
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.55))
            Circle().fill(RadialGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.28)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: size * 0.3, endRadius: size * 0.75))
            // Specular highlight.
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.56, height: size * 0.36)
                .offset(y: -size * 0.2)
            Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
        }
    }
}
