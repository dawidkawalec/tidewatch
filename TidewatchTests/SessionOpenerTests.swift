import Foundation
import Testing
import TidewatchCore
@testable import Tidewatch

@MainActor
struct SessionOpenerTests {
    @Test func buildsTheClaudeExtensionSessionURL() {
        #expect(SessionOpener.sessionURL("2c7f6edd-2153-4800-a181-b41e70f4f557")?.absoluteString == "vscode://anthropic.claude-code/open?session=2c7f6edd-2153-4800-a181-b41e70f4f557")
    }

    @Test func mapsTerminalPrograms() {
        #expect(SessionOpener.terminalBundleId("Apple_Terminal") == "com.apple.Terminal")
        #expect(SessionOpener.terminalBundleId("iTerm.app") == "com.googlecode.iterm2")
        #expect(SessionOpener.terminalBundleId("ghostty") == "com.mitchellh.ghostty")
        #expect(SessionOpener.terminalBundleId("WarpTerminal") == "dev.warp.Warp-Stable")
        #expect(SessionOpener.terminalBundleId(nil) == nil)
        #expect(SessionOpener.terminalBundleId("unknown") == nil)
    }

    private func state(host: SessionHost, terminal: String?) -> SessionState {
        SessionState(sessionId: "s", cwd: "/Users/demo/app", host: host, terminalApp: terminal, pid: nil, now: .now)
    }

    @Test func picksWhatAClickOpens() {
        #expect(SessionOpener.action(for: state(host: .vscode, terminal: nil), vscodeInstalled: true) == .vscodeSession)
        #expect(SessionOpener.action(for: state(host: .vscode, terminal: nil), vscodeInstalled: false) == .finder)
        // CLI in VS Code's terminal: the folder's window, never the session URL.
        #expect(SessionOpener.action(for: state(host: .terminal, terminal: "vscode"), vscodeInstalled: true) == .vscodeFolder)
        #expect(SessionOpener.action(for: state(host: .terminal, terminal: "iTerm.app"), vscodeInstalled: true) == .terminalApp("com.googlecode.iterm2"))
        #expect(SessionOpener.action(for: state(host: .terminal, terminal: nil), vscodeInstalled: true) == .finder)
    }

    @Test func waitsBeforeTheSessionURL() {
        #expect(SessionOpener.uriDelay == .milliseconds(400))
        #expect(SessionOpener.vscodeBundleId == "com.microsoft.VSCode")
    }
}
