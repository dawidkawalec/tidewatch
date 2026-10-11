import AppKit
import Observation
import TidewatchCore

/// The running app: settings, the session store, the widget, hooks and sounds.
@MainActor
@Observable
final class AppState {
    let mode: LaunchMode
    let settings: AppSettings
    let store: SessionStore
    /// Sparkle; live only for a normal launch (never the design preview or the test host).
    let updater: AppUpdater
    private(set) var hookError: String?
    private(set) var launchAtLogin = LaunchAtLogin.isEnabled
    @ObservationIgnored private var widget: WidgetPanelController?
    @ObservationIgnored private let sounds = SoundPlayer()
    @ObservationIgnored private let settingsURL = HookInstaller.defaultSettingsURL()
    @ObservationIgnored private let helperURL = DataPaths.helper()

    init(mode: LaunchMode, defaults: UserDefaults = .standard) {
        self.mode = mode
        settings = AppSettings(defaults: defaults)
        // Only a normal launch reads Claude Code's own files; the preview and the tests never do.
        let system: ClaudeSystem
        if case .normal = mode { system = .live() } else { system = .none }
        let settings = settings
        store = SessionStore(
            fileStore: SessionFileStore(directory: DataPaths.sessions()),
            acknowledged: AcknowledgedStore(defaults: defaults),
            system: system,
            reviewFade: { settings.reviewFade.seconds }
        )
        if case .normal = mode {
            updater = AppUpdater(enabled: true)
        } else {
            updater = AppUpdater(enabled: false)
        }
    }

    func start() {
        switch mode {
        case .tests:
            return
        case .designPreview(let target):
            DesignPreview.run(target: target)
        case .normal:
            refreshHelper()
            repairHooksIfNeeded()
            store.onTransition = { [weak self] transition in
                guard let self else { return }
                if self.sounds.handle(transition, enabled: self.settings.soundsEnabled) {
                    Log.app.notice("sound for \(transition.to.rawValue, privacy: .public)")
                }
            }
            store.start()
            let controller = WidgetPanelController(store: store, settings: settings, actions: actions)
            controller.show()
            widget = controller
            updater.start()
        }
    }

    var actions: WidgetActions {
        WidgetActions(
            open: { [weak self] session in
                self?.store.acknowledge(session)
                self?.widget?.collapse()
                SessionOpener.open(session.state)
            },
            showInFinder: { session in
                SessionOpener.showInFinder(session.state)
            },
            connect: { [weak self] in
                self?.connectHooks()
            },
            restart: {
                AppRestarter.restart()
            }
        )
    }

    // MARK: Hooks

    func connectHooks() {
        do {
            try HelperInstaller.refresh(from: HelperInstaller.bundledHelper(), to: helperURL)
            try HookInstaller.connect(settingsURL: settingsURL, helperPath: helperURL.path)
            settings.hooksConnected = true
            hookError = nil
            Log.hooks.info("connected")
        } catch {
            hookError = error.localizedDescription
            Log.hooks.error("connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disconnectHooks() {
        do {
            try HookInstaller.disconnect(settingsURL: settingsURL)
            settings.hooksConnected = false
            hookError = nil
            Log.hooks.info("disconnected")
        } catch {
            hookError = error.localizedDescription
            Log.hooks.error("disconnect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshHelper() {
        do {
            try HelperInstaller.refresh(from: HelperInstaller.bundledHelper(), to: helperURL)
        } catch {
            Log.hooks.error("helper refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Spec 6.1: after a move or an update, point the hooks at the current helper again.
    private func repairHooksIfNeeded() {
        guard settings.hooksConnected,
              let current = try? HookInstaller.readSettings(at: settingsURL),
              !HookInstaller.isInstalled(current, helperPath: helperURL.path) else { return }
        Log.hooks.info("repairing hook entries")
        connectHooks()
    }

    // MARK: Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            Log.app.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
