import AppKit
import TidewatchCore

/// Brings a session to the front (spec 5.3, verified in the spike): open the project folder in
/// VS Code (focuses the window that has it), then the Claude extension's session URL (focuses
/// that session's tab). Terminal sessions activate their terminal app.
@MainActor
enum SessionOpener {
    static let vscodeBundleId = "com.microsoft.VSCode"
    static let uriDelay: Duration = .milliseconds(400)

    /// What a click on a session does.
    enum Action: Equatable {
        /// Extension session: the folder's VS Code window, then its Claude tab.
        case vscodeSession
        /// CLI in VS Code's terminal: only the folder's window (the session URL would resume it twice).
        case vscodeFolder
        case terminalApp(String)
        case finder
    }

    nonisolated static func action(for state: SessionState, vscodeInstalled: Bool) -> Action {
        if state.host == .vscode { return vscodeInstalled ? .vscodeSession : .finder }
        if state.terminalApp == "vscode" { return vscodeInstalled ? .vscodeFolder : .finder }
        if let bundleId = terminalBundleId(state.terminalApp) { return .terminalApp(bundleId) }
        return .finder
    }

    static func open(_ state: SessionState) {
        let folder = URL(fileURLWithPath: state.cwd, isDirectory: true)
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let vscode = workspace.urlForApplication(withBundleIdentifier: vscodeBundleId)

        switch action(for: state, vscodeInstalled: vscode != nil) {
        case .vscodeSession, .vscodeFolder:
            guard let vscode else { return }
            workspace.open([folder], withApplicationAt: vscode, configuration: configuration) { _, error in
                if let error { Log.ui.error("open folder in VS Code failed: \(error.localizedDescription, privacy: .public)") }
            }
            guard state.host == .vscode else { return }
            let sessionId = state.sessionId
            Task { @MainActor in
                try? await Task.sleep(for: uriDelay)
                if let url = sessionURL(sessionId) { workspace.open(url) }
            }
        case .terminalApp(let bundleId):
            if let app = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                workspace.openApplication(at: app, configuration: configuration) { _, _ in }
            } else {
                showInFinder(state)
            }
        case .finder:
            showInFinder(state)
        }
    }

    static func showInFinder(_ state: SessionState) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: state.cwd, isDirectory: true)])
    }

    nonisolated static func sessionURL(_ sessionId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        return components.url
    }

    nonisolated static func terminalBundleId(_ termProgram: String?) -> String? {
        switch termProgram {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        default: return nil
        }
    }
}
