import SwiftUI

/// "Settings…": the glass and the review lamp. Every change shows on the widget at once; the
/// widget stays expanded while this window is open.
@MainActor
struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// Called after the review fade changed, so the lamps follow at once.
    let reviewFadeChanged: () -> Void

    var body: some View {
        Form {
            Section("Glass") {
                LabeledContent {
                    Slider(value: $settings.glassBlur, in: AppSettings.blurRange, step: 1)
                } label: {
                    valueLabel("Blur", "\(Int(settings.glassBlur)) pt")
                }
                LabeledContent {
                    Slider(value: $settings.glassTint, in: AppSettings.tintRange, step: 0.01)
                } label: {
                    valueLabel("Tint", "\(Int((settings.glassTint * 100).rounded())) %")
                }
                Picker("Appearance", selection: $settings.glassAppearance) {
                    ForEach(AppSettings.GlassAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Text contrast", isOn: $settings.textContrast)
                Text("Dark glass reads best over dark pages, light glass over light ones. Text contrast adds a soft halo under the widget's text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to Defaults") { settings.resetGlass() }
            }
            Section("Lamps") {
                Picker("Review lamp fades", selection: Binding(get: { settings.reviewFade }, set: { fade in
                    settings.reviewFade = fade
                    reviewFadeChanged()
                })) {
                    ForEach(AppSettings.ReviewFade.allCases) { Text($0.label).tag($0) }
                }
                Text("The orange lamp after Claude finishes. Opening the session from the widget or writing in it always ends it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func valueLabel(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 110)
    }
}
