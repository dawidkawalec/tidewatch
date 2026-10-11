import AppKit

/// "Restart Tidewatch": a small shell waits until this process has quit, then opens the app again.
@MainActor
enum AppRestarter {
    /// The shell script; `$0` is the app's path and `$1` this process's pid.
    nonisolated static let script = #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$0""#

    nonisolated static func arguments(appPath: String, pid: Int32) -> [String] {
        ["-c", script, appPath, String(pid)]
    }

    static func restart() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = arguments(appPath: Bundle.main.bundlePath, pid: ProcessInfo.processInfo.processIdentifier)
        do {
            try task.run()
        } catch {
            Log.app.error("restart failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        Log.app.notice("restarting")
        NSApp.terminate(nil)
    }
}
