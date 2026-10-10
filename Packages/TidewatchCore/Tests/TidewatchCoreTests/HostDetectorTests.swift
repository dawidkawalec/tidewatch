import Testing
@testable import TidewatchCore

struct HostDetectorTests {
    @Test func onlyTheExtensionIsAVSCodeSession() {
        #expect(HostDetector.host(["CLAUDE_CODE_ENTRYPOINT": "claude-vscode", "VSCODE_PID": "733"]) == .vscode)
        // The CLI in VS Code's terminal is a terminal session: the extension's session URL would
        // resume it a second time.
        #expect(HostDetector.host(["CLAUDE_CODE_ENTRYPOINT": "cli", "TERM_PROGRAM": "vscode"]) == .terminal)
        #expect(HostDetector.terminalApp(["TERM_PROGRAM": "vscode"]) == "vscode")
    }

    @Test func everythingElseIsATerminal() {
        #expect(HostDetector.host(["CLAUDE_CODE_ENTRYPOINT": "cli", "TERM_PROGRAM": "iTerm.app"]) == .terminal)
        #expect(HostDetector.host([:]) == .terminal)
        #expect(HostDetector.terminalApp(["TERM_PROGRAM": "ghostty"]) == "ghostty")
        #expect(HostDetector.terminalApp(["TERM_PROGRAM": ""]) == nil)
    }
}
