import Foundation
import Observation
import Sparkle

/// "Check for Updates…": a thin wrapper over Sparkle's standard updater controller (copied from
/// Captylo). The controller exists only for a normal launch with a configured feed and key; the
/// design preview and the test host pass `enabled: false` and never reach the network. Even then
/// nothing checks until `start()`, which only `AppState.start()` calls. Sparkle shows its own windows.
@MainActor
@Observable
final class AppUpdater {
    let isConfigured: Bool
    /// "Version 0.3.0 (12)", shown in the menu.
    let versionLine: String
    private(set) var isStarted = false
    /// Sparkle refuses a second check while a session runs (KVO of `canCheckForUpdates`).
    private(set) var canCheckNow = false

    /// For tests: whether a Sparkle controller was created at all.
    var hasController: Bool { controller != nil }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let feedDelegate: FeedDelegate?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init(bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:], enabled: Bool) {
        let environment = ProcessInfo.processInfo.environment
        let configured = enabled && AppUpdaterConfiguration.isConfigured(info: bundleInfo, environment: environment)
        isConfigured = configured
        versionLine = AppUpdaterConfiguration.versionLine(info: bundleInfo)
        guard configured else {
            controller = nil
            feedDelegate = nil
            return
        }
        // Debug builds may point at a local appcast; otherwise the delegate answers nil and
        // Sparkle reads `SUFeedURL` itself.
        let resolved = AppUpdaterConfiguration.feedURL(info: bundleInfo, environment: environment)?.absoluteString
        let plist = bundleInfo[AppUpdaterConfiguration.feedKey] as? String
        let delegate = FeedDelegate(feedURLString: resolved == plist ? nil : resolved)
        feedDelegate = delegate
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
    }

    /// Starts Sparkle's scheduler (a check a day, `SUScheduledCheckInterval`). Idempotent.
    func start() {
        guard let controller, !isStarted else { return }
        controller.startUpdater()
        isStarted = true
        Log.app.info("updater started")
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckNow = updater.canCheckForUpdates
            }
        }
    }

    /// "Check for Updates…": Sparkle's user-initiated check with its own windows.
    func checkNow() {
        guard let controller, isStarted else { return }
        controller.checkForUpdates(nil)
    }
}

/// Answers Sparkle's feed question only when a debug override is set.
@MainActor
private final class FeedDelegate: NSObject, SPUUpdaterDelegate {
    let feedURLString: String?

    init(feedURLString: String?) {
        self.feedURLString = feedURLString
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLString
    }
}
