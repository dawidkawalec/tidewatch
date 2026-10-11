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
        #expect(settings.glassBlur == 8)
        #expect(settings.glassTint == 0.25)
        #expect(settings.glassAppearance == .system)
        #expect(settings.textContrast)
        #expect(settings.reviewFade == .tenMinutes)
        settings.glassBlur = 13
        settings.glassTint = 0.4
        settings.glassAppearance = .dark
        settings.textContrast = false
        settings.reviewFade = .never
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.glassBlur == 13)
        #expect(reloaded.glassTint == 0.4)
        #expect(reloaded.glassAppearance == .dark)
        #expect(!reloaded.textContrast)
        #expect(reloaded.reviewFade == .never)
    }

    @Test func glassValuesStayInTheirRanges() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "tw-settings-\(UUID().uuidString)")!)
        settings.glassBlur = 99
        settings.glassTint = -1
        #expect(settings.glassBlur == AppSettings.blurRange.upperBound)
        #expect(settings.glassTint == AppSettings.tintRange.lowerBound)
        settings.resetGlass()
        #expect(settings.glassBlur == 8)
        #expect(settings.glassTint == 0.25)
        #expect(settings.glassAppearance == .system)
        #expect(settings.textContrast)
    }

    @Test func reviewFadeChoicesMapToSeconds() {
        #expect(AppSettings.ReviewFade.allCases.map(\.seconds) == [300, 600, 1800, nil])
    }
}
