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

    @Test func glassAndReviewFadeDefaultAndPersist() {
        let defaults = UserDefaults(suiteName: "tw-settings-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.glassBlur == .medium)
        #expect(settings.glassTint == .standard)
        #expect(settings.reviewFade == .tenMinutes)
        settings.glassBlur = .strong
        settings.glassTint = .darker
        settings.reviewFade = .never
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.glassBlur == .strong)
        #expect(reloaded.glassTint == .darker)
        #expect(reloaded.reviewFade == .never)
    }

    @Test func choicesMapToValues() {
        #expect(AppSettings.GlassBlur.allCases.map(\.radius) == [4, 8, 14])
        #expect(AppSettings.GlassTint.lighter.fill < AppSettings.GlassTint.standard.fill)
        #expect(AppSettings.GlassTint.standard.fill < AppSettings.GlassTint.darker.fill)
        #expect(AppSettings.ReviewFade.allCases.map(\.seconds) == [300, 600, 1800, nil])
    }
}
