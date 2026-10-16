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
    private var fixedCanvasHeight: CGFloat?
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
        hostingView.onScroll = { [weak self] deltaY in self?.scroll(by: deltaY) ?? false }
    }

    /// A wheel or trackpad scroll over the open panel moves the session list. Returns false when the
    /// list has nothing to scroll, so the event goes on as usual.
    private func scroll(by deltaY: CGFloat) -> Bool {
        let metrics = self.metrics
        guard model.isExpanded, metrics.scrolls,
              metrics.panelRect.contains(canvasPoint(NSEvent.mouseLocation)) else { return false }
        let next = metrics.clampedScroll(model.scrollOffset - deltaY)
        if next != model.scrollOffset { model.scrollOffset = next }
        evaluatePointer()
        return true
    }

    /// The geometry for the sessions shown now on the current canvas.
    private var metrics: WidgetMetrics { store.metrics(canvasHeight: model.canvasHeight) }

    /// `watchPointer: false` leaves hover and expansion to the caller (the design preview's demo).
    /// `canvasHeight`: a fixed canvas (the preview's 600); nil is the screen's visible height.
    func show(pinnedExpanded: Bool = false, watchPointer: Bool = true, canvasHeight: CGFloat? = nil) {
        model.isExpansionPinned = pinnedExpanded
        model.isExpanded = pinnedExpanded
        watchesPointer = watchPointer
        fixedCanvasHeight = canvasHeight
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

    /// The canvas covers the right edge of the menu bar screen, top to bottom of its visible
    /// frame (transparent pixels let clicks through), so the widget can grow to the screen.
    private func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = WidgetMetrics.canvasFrame(in: screen.visibleFrame, height: fixedCanvasHeight)
        model.canvasHeight = frame.height
        panel.setFrame(frame, display: true)
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
        let metrics = self.metrics
        let point = canvasPoint(NSEvent.mouseLocation)
        let offset = metrics.clampedScroll(model.scrollOffset)
        let hovered = metrics.lampIndex(at: point) ?? (model.isExpanded ? metrics.rowIndex(at: point, offset: offset) : nil)
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
            let metrics = self.metrics
            guard metrics.hoverRect(expanded: self.model.isExpanded).contains(self.canvasPoint(NSEvent.mouseLocation)) == wanted else { return }
            self.setExpanded(wanted)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        // The list opens at the top again.
        if !expanded { model.scrollOffset = 0 }
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
