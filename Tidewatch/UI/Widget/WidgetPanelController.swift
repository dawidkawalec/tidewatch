import AppKit
import SwiftUI

/// Owns the widget panel: glues it to the right edge of the menu bar screen, expands it on hover
/// (Captylo's dwell and grace delays) and tracks which lamp or row is under the pointer. Never
/// activates the app.
@MainActor
final class WidgetPanelController {
    let model: WidgetModel
    private let store: SessionStore
    private let panel = WidgetPanel()
    private let hostingView: WidgetHostingView
    private var pointerTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var hoverTarget: Bool?
    private var screenObserver: NSObjectProtocol?
    private var watchesPointer = true
    private let settings: AppSettings

    var windowNumber: Int { panel.windowNumber }
    var frame: NSRect { panel.frame }

    init(store: SessionStore, settings: AppSettings, actions: WidgetActions, model: WidgetModel = WidgetModel()) {
        self.store = store
        self.settings = settings
        self.model = model
        hostingView = WidgetHostingView(rootView: WidgetRootView(store: store, model: model, settings: settings, actions: actions))
        panel.contentView = hostingView
        hostingView.onPointer = { [weak self] in self?.evaluatePointer() }
    }

    /// `watchPointer: false` leaves hover and expansion to the caller (the design preview's demo).
    func show(pinnedExpanded: Bool = false, watchPointer: Bool = true) {
        model.isExpansionPinned = pinnedExpanded
        model.isExpanded = pinnedExpanded
        watchesPointer = watchPointer
        reposition()
        panel.orderFrontRegardless()
        applyGlass()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        if watchPointer { startPointerWatch() }
        Log.ui.debug("widget shown")
    }

    /// The window's blur radius and appearance from the settings, again whenever they change.
    private func applyGlass() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let (radius, appearance) = withObservationTracking {
            (settings.glassBlur, settings.glassAppearance)
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyGlass() }
        }
        panel.appearance = appearance.nsAppearance
        WindowBlur.set(reduce ? 0 : Int(radius.rounded()), on: panel)
    }

    /// While the settings window is open the panel stays expanded, so every change shows.
    func setPinnedOpen(_ pinned: Bool) {
        guard watchesPointer else { return }
        model.isExpansionPinned = pinned
        if pinned { setExpanded(true) } else { evaluatePointer() }
    }

    /// Closes the panel at once (after a click on a row).
    func collapse() {
        guard !model.isExpansionPinned else { return }
        hoverTask?.cancel()
        hoverTask = nil
        hoverTarget = nil
        setExpanded(false)
    }

    private func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        panel.setFrameOrigin(WidgetMetrics.canvasOrigin(in: screen.visibleFrame))
    }

    // MARK: Pointer

    /// The tracking area answers at once; the 150 ms poll covers what it cannot see (the pointer
    /// resting over transparent canvas pixels, which belong to the window below).
    private func startPointerWatch() {
        pointerTask?.cancel()
        pointerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: WidgetMetrics.pointerPoll)
                self?.evaluatePointer()
            }
        }
    }

    private func evaluatePointer() {
        guard watchesPointer else { return }
        let metrics = store.metrics
        let point = canvasPoint(NSEvent.mouseLocation)
        let hovered = metrics.lampIndex(at: point) ?? (model.isExpanded ? metrics.rowIndex(at: point) : nil)
        if hovered != model.hoveredIndex { model.hoveredIndex = hovered }

        guard !model.isExpansionPinned else { return }
        let wanted = metrics.hoverRect(expanded: model.isExpanded).contains(point)
        guard wanted != model.isExpanded else {
            hoverTask?.cancel()
            hoverTask = nil
            hoverTarget = nil
            return
        }
        guard hoverTarget != wanted else { return }
        hoverTarget = wanted
        hoverTask?.cancel()
        let delay = wanted ? WidgetMetrics.expandDelay : WidgetMetrics.collapseDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            self.hoverTarget = nil
            let metrics = self.store.metrics
            guard metrics.hoverRect(expanded: self.model.isExpanded).contains(self.canvasPoint(NSEvent.mouseLocation)) == wanted else { return }
            self.setExpanded(wanted)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? GlassMotion.reduced : GlassMotion.liquid) {
            model.isExpanded = expanded
        }
    }

    /// Screen point to canvas coordinates (origin bottom left).
    private func canvasPoint(_ screenPoint: NSPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    }
}
