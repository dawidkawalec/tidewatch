import Foundation

/// Links into the T3 Code desktop app (read from its 0.1.9 bundle, 2026-11-15): the app routes
/// `t3code://threads/<environmentId>/<threadId>` to that thread. The environment id is the local
/// T3 server's, stored in `~/.t3/userdata/environment-id` (read-only for Tidewatch).
public enum T3Link {
    public static let bundleId = "com.t3tools.t3code"

    public static func threadURL(environmentId: String, threadId: String) -> URL? {
        guard !environmentId.isEmpty, !threadId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "t3code"
        components.host = "threads"
        components.path = "/\(environmentId)/\(threadId)"
        return components.url
    }

    /// T3's data folder: `T3CODE_HOME` when set, else `~/.t3`.
    public static func home(environment: [String: String], userHome: URL) -> URL {
        if let custom = environment["T3CODE_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return userHome.appendingPathComponent(".t3", isDirectory: true)
    }

    /// The local T3 server's environment id, nil when T3 is not set up.
    public static func environmentId(home: URL) -> String? {
        let file = home.appendingPathComponent("userdata/environment-id")
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The `t3` command line tool (`t3 app <folder>` opens a project in the running app).
    public static func cli(home: URL) -> URL {
        home.appendingPathComponent("bin/t3")
    }
}
