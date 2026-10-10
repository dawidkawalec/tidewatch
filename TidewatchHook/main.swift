import Foundation
import os
import TidewatchCore

// Called by Claude Code hooks with one event JSON on stdin (spec 6.1). Never prints, never
// touches the network and always exits 0, so it can never block or change Claude's behaviour.
let log = Logger(subsystem: "pl.craftweb.tidewatch", category: "hook")
let environment = ProcessInfo.processInfo.environment
let input = FileHandle.standardInput.readDataToEndOfFile()

do {
    let event = try HookEvent.decode(input)
    let context = EventContext(
        now: Date(),
        host: HostDetector.host(environment),
        terminalApp: HostDetector.terminalApp(environment),
        // The hook command is a direct child of the Claude Code process (spike 6.3).
        pid: getppid()
    )
    try SessionFileStore(directory: DataPaths.sessions(environment: environment)).apply(event, context: context)
} catch {
    log.error("hook event skipped: \(String(describing: error), privacy: .public)")
}
exit(0)
