import AppKit
import SwiftUI

/// The settings window. Opening it activates Tidewatch (an explicit request, unlike the widget,
/// which never takes focus); `onVisibilityChange` keeps the widget expanded while it is in front.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let reviewFadeChanged: () -> Void
    private let onVisibilityChange: (Bool) -> Void
    private var window: NSWindow?

    init(settings: AppSettings, reviewFadeChanged: @escaping () -> Void, onVisibilityChange: @escaping (Bool) -> Void) {
        self.settings = settings
        self.reviewFadeChanged = reviewFadeChanged
        self.onVisibilityChange = onVisibilityChange
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onVisibilityChange(true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, reviewFadeChanged: reviewFadeChanged))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Tidewatch Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        // Left of centre, so the widget on the right edge stays in view.
        if let screen = window.screen ?? NSScreen.main {
            var origin = window.frame.origin
            origin.x = screen.visibleFrame.midX - window.frame.width - 40
            window.setFrameOrigin(origin)
        }
        return window
    }

    // The widget stays expanded only while this window is in front: a click anywhere else lets it
    // collapse, coming back expands it again.
    func windowDidBecomeKey(_ notification: Notification) {
        onVisibilityChange(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        onVisibilityChange(false)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange(false)
    }
}
