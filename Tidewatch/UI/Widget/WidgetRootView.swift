import SwiftUI

/// The whole canvas: the lamp column and, while expanded, the session panel, both placed from
/// `WidgetMetrics` (top-left SwiftUI coordinates = canvas height - AppKit y).
@MainActor
struct WidgetRootView: View {
    let store: SessionStore
    let model: WidgetModel
    let settings: AppSettings
    let actions: WidgetActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = store.metrics(canvasHeight: model.canvasHeight)
        let height = metrics.canvas.height
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.isExpanded {
                SessionPanelView(groups: store.groups, hoveredIndex: model.hoveredIndex, scrollOffset: model.scrollOffset, isConnected: settings.hooksConnected, metrics: metrics, actions: actions)
                    .textHalo(settings.textContrast)
                    .frame(width: metrics.panelRect.width, height: metrics.panelRect.height)
                    .widgetGlass(in: RoundedRectangle(cornerRadius: GlassTokens.Radius.panel, style: .continuous), tint: settings.glassTint)
                    .position(x: metrics.panelRect.midX, y: height - metrics.panelRect.midY)
                    .transition(reduceMotion ? .opacity : Self.emerge)
            }
            LampColumn(sessions: store.sessions, hoveredIndex: model.hoveredIndex, metrics: metrics, actions: actions)
                .frame(width: metrics.columnRect.width, height: metrics.columnRect.height)
                .widgetGlass(in: Capsule(style: .continuous), tint: settings.glassTint)
                .position(x: metrics.columnRect.midX, y: height - metrics.columnRect.midY)
        }
        .frame(width: metrics.canvas.width, height: height)
        // The capsule grows and shrinks like liquid when sessions come and go.
        .animation(reduceMotion ? nil : GlassMotion.liquid, value: store.sessions.map(\.id))
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
