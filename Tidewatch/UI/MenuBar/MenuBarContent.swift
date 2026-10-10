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
        Text("Tip: the first click asks VS Code to allow the Claude link once. Tick \"Do not ask me again\".")
        Divider()
        Button("Quit Tidewatch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
