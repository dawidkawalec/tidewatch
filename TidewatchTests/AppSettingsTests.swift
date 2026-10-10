import Foundation
import Testing
@testable import Tidewatch

@MainActor
struct AppSettingsTests {
    @Test func soundsDefaultOnAndPersist() {
        let defaults = UserDefaults(suiteName: "tw-settings-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.soundsEnabled)
        #expect(!settings.hooksConnected)
        settings.soundsEnabled = false
        settings.hooksConnected = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.soundsEnabled)
        #expect(reloaded.hooksConnected)
    }
}
