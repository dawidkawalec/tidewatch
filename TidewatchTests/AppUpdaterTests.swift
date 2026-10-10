import Foundation
import Testing
@testable import Tidewatch

/// Sparkle setup (copied from Captylo): the updater runs only with a real feed and EdDSA key in a
/// public build, never in the design preview or the test host.
struct AppUpdaterConfigurationTests {
    private let feed = "https://kawalec.pl/tidewatch/updates/appcast.xml"
    private let key = "pGg3aW1lc3RhbXAtcHVibGljLWtleS1mb3ItdGVzdHM="

    @Test func feedURLComesFromTheInfoDictionary() {
        #expect(AppUpdaterConfiguration.feedURL(info: ["SUFeedURL": feed], environment: [:]) == URL(string: feed))
    }

    @Test func feedURLMissingOrBrokenIsNil() {
        #expect(AppUpdaterConfiguration.feedURL(info: [:], environment: [:]) == nil)
        #expect(AppUpdaterConfiguration.feedURL(info: ["SUFeedURL": ""], environment: [:]) == nil)
        #expect(AppUpdaterConfiguration.feedURL(info: ["SUFeedURL": "appcast.xml"], environment: [:]) == nil)
        #expect(AppUpdaterConfiguration.feedURL(info: ["SUFeedURL": "file:///tmp/appcast.xml"], environment: [:]) == nil)
        #expect(AppUpdaterConfiguration.feedURL(info: ["SUFeedURL": 42], environment: [:]) == nil)
    }

    /// A local appcast for testing an update end to end; only debug builds read it.
    @Test func debugBuildsTakeTheEnvironmentOverride() {
        let local = "http://127.0.0.1:8123/appcast.xml"
        let url = AppUpdaterConfiguration.feedURL(info: ["SUFeedURL": feed], environment: ["TIDEWATCH_APPCAST_URL": local])
        #if DEBUG
        #expect(url == URL(string: local))
        #else
        #expect(url == URL(string: feed))
        #endif
        let broken = AppUpdaterConfiguration.feedURL(info: ["SUFeedURL": feed], environment: ["TIDEWATCH_APPCAST_URL": "nope"])
        #expect(broken == URL(string: feed))
    }

    @Test func placeholderEmptyOrUnexpandedKeyIsNotConfigured() {
        for value in [AppUpdaterConfiguration.placeholderKey, "", "   ", "$(SPARKLE_PUBLIC_ED_KEY)"] {
            let info: [String: Any] = ["SUFeedURL": feed, "SUPublicEDKey": value, "CFBundleVersion": "12"]
            #expect(AppUpdaterConfiguration.publicKey(info: info) == nil)
            #expect(!AppUpdaterConfiguration.isConfigured(info: info, environment: [:]))
        }
    }

    @Test func realKeyFeedAndPublicBuildAreConfigured() {
        let info: [String: Any] = ["SUFeedURL": feed, "SUPublicEDKey": key, "CFBundleVersion": "12"]
        #expect(AppUpdaterConfiguration.publicKey(info: info) == key)
        #expect(AppUpdaterConfiguration.isConfigured(info: info, environment: [:]))
        #expect(!AppUpdaterConfiguration.isConfigured(info: ["SUPublicEDKey": key, "CFBundleVersion": "12"], environment: [:]))
    }

    /// `make release` keeps build number 1; only `make dist` stamps the commit count. A development
    /// copy must never be offered the public build over itself.
    @Test func developmentBuildNeverUpdates() {
        let dev: [String: Any] = ["SUFeedURL": feed, "SUPublicEDKey": key, "CFBundleVersion": "1"]
        #expect(!AppUpdaterConfiguration.isConfigured(info: dev, environment: [:]))
    }

    @Test func buildNumberParsesWholeNumbersOnly() {
        #expect(AppUpdaterConfiguration.buildNumber(info: ["CFBundleVersion": "142"]) == 142)
        #expect(AppUpdaterConfiguration.buildNumber(info: ["CFBundleVersion": " 7 "]) == 7)
        #expect(AppUpdaterConfiguration.buildNumber(info: ["CFBundleVersion": "1.2"]) == nil)
        #expect(AppUpdaterConfiguration.buildNumber(info: ["CFBundleVersion": "-3"]) == nil)
        #expect(AppUpdaterConfiguration.buildNumber(info: [:]) == nil)
    }

    @Test func versionLineShowsTheBuildWhenThereIsOne() {
        #expect(AppUpdaterConfiguration.versionLine(info: ["CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "12"]) == "Version 0.3.0 (12)")
        #expect(AppUpdaterConfiguration.versionLine(info: ["CFBundleShortVersionString": "0.3.0"]) == "Version 0.3.0")
        #expect(AppUpdaterConfiguration.versionLine(info: [:]) == "Version ?")
    }

    /// The test host is the app: its Info.plist points at the download page and checks daily.
    @Test func shippedInfoPlistHasTheFeed() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(AppUpdaterConfiguration.feedURL(info: info, environment: [:]) == URL(string: feed))
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86400)
    }
}

@MainActor
struct AppUpdaterTests {
    private let feed = "https://kawalec.pl/tidewatch/updates/appcast.xml"
    private let key = "pGg3aW1lc3RhbXAtcHVibGljLWtleS1mb3ItdGVzdHM="

    @Test func disabledUpdaterHasNoControllerAndNeverStarts() {
        let updater = AppUpdater(bundleInfo: ["SUFeedURL": feed, "SUPublicEDKey": key, "CFBundleVersion": "12"], enabled: false)
        #expect(!updater.isConfigured)
        #expect(!updater.hasController)
        updater.start()
        updater.checkNow()
        #expect(!updater.isStarted)
    }

    @Test func unconfiguredUpdaterStaysOff() {
        let updater = AppUpdater(bundleInfo: ["SUFeedURL": feed, "SUPublicEDKey": AppUpdaterConfiguration.placeholderKey, "CFBundleVersion": "12"], enabled: true)
        #expect(!updater.hasController)
        updater.start()
        #expect(!updater.isStarted)
    }

    /// Sparkle's controller is built but nothing checks until `start()`; `checkNow()` before that
    /// is ignored, so the test host never opens a Sparkle window or touches the network.
    @Test func configuredUpdaterWaitsForStart() {
        let info: [String: Any] = ["SUFeedURL": feed, "SUPublicEDKey": key, "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "12"]
        let updater = AppUpdater(bundleInfo: info, enabled: true)
        #expect(updater.isConfigured)
        #expect(updater.hasController)
        #expect(!updater.isStarted)
        #expect(updater.versionLine == "Version 0.3.0 (12)")
        updater.checkNow()
        #expect(!updater.isStarted)
    }
}
