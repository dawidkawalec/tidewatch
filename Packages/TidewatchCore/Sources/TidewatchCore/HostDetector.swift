/// Where a session runs, from the hook process environment (verified in the spike: the VS Code
/// extension sets `CLAUDE_CODE_ENTRYPOINT=claude-vscode`; T3 Code sets `t3-code` and passes the
/// thread in `T3CODE_THREAD_ID`). The CLI in VS Code's own terminal is a terminal session
/// (`terminalApp == "vscode"`): the extension's session URL would resume it twice.
public enum HostDetector {
    public static func host(_ environment: [String: String]) -> SessionHost {
        host(entrypoint: environment["CLAUDE_CODE_ENTRYPOINT"])
    }

    /// The same mapping for the `entrypoint` of Claude Code's session registry.
    public static func host(entrypoint: String?) -> SessionHost {
        switch entrypoint {
        case "claude-vscode": return .vscode
        case "t3-code": return .t3
        default: return .terminal
        }
    }

    public static func terminalApp(_ environment: [String: String]) -> String? {
        guard let value = environment["TERM_PROGRAM"], !value.isEmpty else { return nil }
        return value
    }

    /// The T3 Code thread that runs the session, nil outside T3.
    public static func t3ThreadId(_ environment: [String: String]) -> String? {
        guard let value = environment["T3CODE_THREAD_ID"], !value.isEmpty else { return nil }
        return value
    }
}
