import AppKit
import TidewatchCore

/// `--design-preview <target>`: the widget on invented sessions (the names from the mockups), in
/// a temp folder, with its own defaults. Never touches the real data folder or settings.json.
/// Prints `WINDOW_ID=` and `WINDOW_FRAME=x,y,w,h` (top-left screen coordinates) for snap.sh.
@MainActor
enum DesignPreview {
    enum Target: String, CaseIterable {
        case collapsed = "widget-collapsed"
        case expanded = "widget-expanded"
        case empty = "widget-empty"
        case overflow = "widget-overflow"
        case disconnected = "widget-disconnected"
        /// The scripted, looping cycle in DesignPreviewDemo.swift.
        case demo = "widget-demo"
    }

    private static var retained: [AnyObject] = []

    static func sessions(for target: Target, now: Date) -> [SessionState] {
        func make(_ order: Int, _ name: String, _ status: SessionStatus, _ activity: SessionActivity = .working, minutes: Double, tool: String? = nil, detail: String? = nil) -> SessionState {
            var state = SessionState(sessionId: "preview-\(order)", cwd: "/Users/demo/\(name)", host: .vscode, terminalApp: nil, pid: nil, now: now)
            state.status = status
            state.activity = activity
            state.tool = tool
            state.detail = detail
            state.statusSince = now.addingTimeInterval(-minutes * 60)
            state.lastEvent = now.addingTimeInterval(-min(minutes, 5) * 60)
            state.firstSeen = now.addingTimeInterval(-Double(100 - order) * 60)
            return state
        }
        let five = [
            make(1, "Captylo", .working, .coding, minutes: 2),
            make(2, "Zorko", .needsApproval, minutes: 5, tool: "Bash", detail: "npm install"),
            make(3, "Omnira", .working, .runningTests, minutes: 12),
            make(4, "Craftweb", .idle, minutes: 60),
            make(5, "Blog AI", .working, .researching, minutes: 3),
        ]
        switch target {
        case .collapsed, .expanded:
            return five
        case .empty, .disconnected:
            return []
        case .demo:
            return Demo.sessions(for: Demo.initial, now: now)
        case .overflow:
            return five + [
                make(6, "Snapfeed", .awaitingReview, minutes: 1),
                make(7, "Atlas", .working, .readingCode, minutes: 4),
                make(8, "Harbor", .idle, minutes: 90),
                make(9, "Lumen", .working, .runningAgents, minutes: 7),
            ]
        }
    }

    static func run(target raw: String) {
        guard let target = Target(rawValue: raw) else {
            print("Unknown design preview target '\(raw)'. Targets: \(Target.allCases.map(\.rawValue).joined(separator: " "))")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        switch ProcessInfo.processInfo.environment["TIDEWATCH_PREVIEW_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        let now = Date()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tidewatch-preview-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = SessionFileStore(directory: folder)
        for state in sessions(for: target, now: now) {
            try? files.write(state, to: files.fileURL(for: state.sessionId))
        }
        let suite = "tidewatch-preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let isDemo = target == .demo
        let store = SessionStore(fileStore: files, acknowledged: AcknowledgedStore(defaults: defaults), isAlive: { _ in true }, clock: { isDemo ? Date() : now })
        store.reload()
        let settings = AppSettings(defaults: defaults)
        settings.hooksConnected = target != .disconnected

        guard let screen = NSScreen.screens.first else { return }
        let origin = WidgetMetrics.canvasOrigin(in: screen.visibleFrame)
        let frame = NSRect(origin: origin, size: WidgetMetrics.canvas)
        if let path = ProcessInfo.processInfo.environment["TIDEWATCH_PREVIEW_BACKDROP"], let image = NSImage(contentsOfFile: path) {
            let backdrop = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            backdrop.level = .floating
            let view = NSImageView(image: image)
            view.imageScaling = .scaleAxesIndependently
            backdrop.contentView = view
            backdrop.orderFrontRegardless()
            retained.append(backdrop)
        }

        let controller = WidgetPanelController(store: store, settings: settings, actions: .preview)
        // The demo drives expansion and hover itself; the pointer must not take them over.
        controller.show(pinnedExpanded: target != .collapsed, watchPointer: !isDemo)
        if isDemo {
            Demo.play(store: store, files: files, model: controller.model)
        }
        retained.append(store)
        retained.append(controller)
        retained.append(settings)

        let shown = controller.frame
        print("WINDOW_ID=\(controller.windowNumber)")
        print("WINDOW_FRAME=\(Int(shown.minX)),\(Int(screen.frame.height - shown.maxY)),\(Int(shown.width)),\(Int(shown.height))")
        fflush(stdout)
    }
}
