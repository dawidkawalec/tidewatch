import Foundation

/// `~/Library/Application Support/Tidewatch/`, or `TIDEWATCH_DATA_DIR` (tests, previews).
public enum DataPaths {
    public static func root(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["TIDEWATCH_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tidewatch", isDirectory: true)
    }

    public static func sessions(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(environment: environment).appendingPathComponent("sessions", isDirectory: true)
    }

    /// The stable helper copy the hooks in settings.json point to.
    public static func helper(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(environment: environment).appendingPathComponent("bin", isDirectory: true).appendingPathComponent("tidewatch-hook")
    }
}
