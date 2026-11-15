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

    @Test func t3CodeSessionsKeepTheirThread() {
        let environment = ["CLAUDE_CODE_ENTRYPOINT": "t3-code", "T3CODE_THREAD_ID": "00000000-0000-4000-8000-000000000002"]
        #expect(HostDetector.host(environment) == .t3)
        #expect(HostDetector.t3ThreadId(environment) == "00000000-0000-4000-8000-000000000002")
        #expect(HostDetector.t3ThreadId(["T3CODE_THREAD_ID": ""]) == nil)
        #expect(HostDetector.t3ThreadId([:]) == nil)
        // Claude Code's registry uses the same entrypoint names.
        #expect(HostDetector.host(entrypoint: "t3-code") == .t3)
        #expect(HostDetector.host(entrypoint: "claude-vscode") == .vscode)
        #expect(HostDetector.host(entrypoint: nil) == .terminal)
    }

    @Test func everythingElseIsATerminal() {
        #expect(HostDetector.host(["CLAUDE_CODE_ENTRYPOINT": "cli", "TERM_PROGRAM": "iTerm.app"]) == .terminal)
        #expect(HostDetector.host([:]) == .terminal)
        #expect(HostDetector.terminalApp(["TERM_PROGRAM": "ghostty"]) == "ghostty")
        #expect(HostDetector.terminalApp(["TERM_PROGRAM": ""]) == nil)
    }
}
