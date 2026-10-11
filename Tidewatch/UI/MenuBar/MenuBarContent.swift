import SwiftUI

@MainActor
struct MenuBarContent: View {
    let state: AppState

    var body: some View {
        if state.settings.hooksConnected {
            Text("Connected to Claude Code")
            Button("Disconnect") { state.disconnectHooks() }
        } else {
            Button("Connect to Claude Code") { state.connectHooks() }
        }
        if let error = state.hookError {
            Text(error)
        }
        Divider()
        Toggle("Sounds", isOn: Bindable(state.settings).soundsEnabled)
        Toggle("Launch at Login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
        Divider()
        Picker("Glass Blur", selection: Bindable(state.settings).glassBlur) {
            ForEach(AppSettings.GlassBlur.allCases) { Text($0.label).tag($0) }
        }
        Picker("Glass Tint", selection: Bindable(state.settings).glassTint) {
            ForEach(AppSettings.GlassTint.allCases) { Text($0.label).tag($0) }
        }
        Picker("Review Lamp Fades", selection: Binding(get: { state.settings.reviewFade }, set: { fade in
            state.settings.reviewFade = fade
            state.store.reload()
        })) {
            ForEach(AppSettings.ReviewFade.allCases) { Text($0.label).tag($0) }
        }
        Divider()
        Text("Tip: the first click asks VS Code to allow the Claude link once. Tick \"Do not ask me again\".")
        Divider()
        Text(state.updater.versionLine)
        Button("Check for Updates…") { state.updater.checkNow() }
            .disabled(!state.updater.isConfigured || !state.updater.canCheckNow)
        Divider()
        Button("Restart Tidewatch") { AppRestarter.restart() }
        Button("Quit Tidewatch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
