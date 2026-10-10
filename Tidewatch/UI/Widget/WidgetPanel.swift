import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that never becomes key or main (Captylo's
/// RecorderPanel). Transparent canvas pixels let clicks through to the windows below.
final class WidgetPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: WidgetMetrics.canvas),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        // Liquid Glass follows the window's appearance: in light mode over white documents it
        // turns pale grey and the white type loses contrast. The widget is always dark glass.
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false
        animationBehavior = .utilityWindow
        isMovable = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view with a tracking area that works while the app is inactive, and first-click
/// support so rows react without activating Tidewatch.
final class WidgetHostingView: NSHostingView<WidgetRootView> {
    var onPointer: (@MainActor () -> Void)?
    private var hoverArea: NSTrackingArea?

    required init(rootView: WidgetRootView) {
        super.init(rootView: rootView)
        sizingOptions = []
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointer?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointer?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointer?()
    }
}
