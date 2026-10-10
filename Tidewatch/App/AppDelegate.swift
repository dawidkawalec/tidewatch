import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState(mode: LaunchMode.current())

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
    }
}
