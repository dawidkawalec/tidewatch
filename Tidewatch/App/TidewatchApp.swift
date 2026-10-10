import SwiftUI

@main
struct TidewatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(state: appDelegate.state)
        } label: {
            Image(systemName: "smallcircle.filled.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
