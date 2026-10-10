import SwiftUI

/// The whole canvas: the lamp column and, while expanded, the session panel, both placed from
/// `WidgetMetrics` (top-left SwiftUI coordinates = canvas height - AppKit y).
@MainActor
struct WidgetRootView: View {
    let store: SessionStore
    let model: WidgetModel
    let settings: AppSettings
    let actions: WidgetActions
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = WidgetMetrics(sessionCount: store.sessions.count)
        let height = WidgetMetrics.canvas.height
        GlassContainer {
            ZStack(alignment: .topLeading) {
                Color.clear
                if model.isExpanded {
                    SessionPanelView(sessions: store.sessions, hoveredIndex: model.hoveredIndex, isConnected: settings.hooksConnected, actions: actions)
                        .frame(width: metrics.panelRect.width, height: metrics.panelRect.height)
                        .widgetGlass("panel", in: RoundedRectangle(cornerRadius: GlassTokens.Radius.panel, style: .continuous), namespace: glass)
                        .position(x: metrics.panelRect.midX, y: height - metrics.panelRect.midY)
                        .transition(reduceMotion ? .opacity : Self.emerge)
                }
                LampColumn(sessions: store.sessions, hoveredIndex: model.hoveredIndex, metrics: metrics)
                    .frame(width: metrics.columnRect.width, height: metrics.columnRect.height)
                    .widgetGlass("column", in: Capsule(style: .continuous), namespace: glass)
                    .position(x: metrics.columnRect.midX, y: height - metrics.columnRect.midY)
            }
            .frame(width: WidgetMetrics.canvas.width, height: height)
            // The capsule grows and shrinks like liquid when sessions come and go.
            .animation(reduceMotion ? nil : GlassMotion.liquid, value: store.sessions.map(\.id))
        }
        .environment(\.appearsActive, true)
        .environment(\.controlActiveState, .key)
        .ignoresSafeArea()
    }

    /// The panel wells out of the column: it starts small and pushed into the column (inside the
    /// glass merge distance, so both shapes flow together), then springs left and detaches like a
    /// drop of Liquid Glass. It falls back into the column on the way out.
    private static var emerge: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.35, anchor: .trailing)).combined(with: .offset(x: 34)),
            removal: .opacity.combined(with: .scale(scale: 0.55, anchor: .trailing)).combined(with: .offset(x: 26))
        )
    }
}
