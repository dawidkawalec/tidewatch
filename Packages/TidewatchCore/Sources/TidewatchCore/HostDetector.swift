/// Where a session runs, from the hook process environment (verified in the spike: the VS Code
/// extension sets `CLAUDE_CODE_ENTRYPOINT=claude-vscode`). The CLI in VS Code's own terminal is a
/// terminal session (`terminalApp == "vscode"`): the extension's session URL would resume it twice.
public enum HostDetector {
    public static func host(_ environment: [String: String]) -> SessionHost {
        environment["CLAUDE_CODE_ENTRYPOINT"] == "claude-vscode" ? .vscode : .terminal
    }

    public static func terminalApp(_ environment: [String: String]) -> String? {
        guard let value = environment["TERM_PROGRAM"], !value.isEmpty else { return nil }
        return value
    }
}
