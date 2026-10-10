import Foundation

enum HookInstallerError: Error, LocalizedError, Equatable {
    case invalidJSON

    var errorDescription: String? {
        "~/.claude/settings.json is not valid JSON, so Tidewatch left it untouched."
    }
}

/// Adds and removes Tidewatch's own hook entries in Claude Code's user settings (spec 6.1).
/// Entries are recognised by the helper path; every other key and hook stays as it is.
enum HookInstaller {
    static let marker = "/Tidewatch/bin/tidewatch-hook"
    static let timeout = 5
    static let events: [(name: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("SessionEnd", nil),
        ("UserPromptSubmit", nil),
        ("PreToolUse", "*"),
        ("PostToolUse", "*"),
        ("PostToolUseFailure", "*"),
        ("PermissionRequest", "*"),
        ("Notification", nil),
        ("Stop", nil),
        ("SubagentStart", nil),
        ("PreCompact", nil),
    ]

    static func command(helperPath: String) -> String {
        "\"\(helperPath)\""
    }

    static func defaultSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    // MARK: Pure

    static func installing(into settings: [String: Any], helperPath: String) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event.name] as? [Any] ?? []
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command(helperPath: helperPath), "timeout": timeout]],
            ]
            if let matcher = event.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[event.name] = groups
        }
        result["hooks"] = hooks
        return result
    }

    static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var changed = false
        for (name, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept = groups.filter { !isTidewatchGroup($0) }
            guard kept.count != groups.count else { continue }
            changed = true
            if kept.isEmpty { hooks.removeValue(forKey: name) } else { hooks[name] = kept }
        }
        guard changed else { return settings }
        var result = settings
        if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
        return result
    }

    /// A matcher group whose every command is the Tidewatch helper.
    static func isTidewatchGroup(_ group: Any) -> Bool {
        guard let group = group as? [String: Any], let entries = group["hooks"] as? [Any], !entries.isEmpty else {
            return false
        }
        return entries.allSatisfy { ((($0 as? [String: Any])?["command"]) as? String)?.contains(marker) == true }
    }

    static func isInstalled(_ settings: [String: Any], helperPath: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        let expected = command(helperPath: helperPath)
        return events.allSatisfy { event in
            (hooks[event.name] as? [Any] ?? []).contains { group in
                guard isTidewatchGroup(group), let entries = (group as? [String: Any])?["hooks"] as? [Any] else { return false }
                return entries.contains { (($0 as? [String: Any])?["command"] as? String) == expected }
            }
        }
    }

    // MARK: File

    static func readSettings(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data), let settings = object as? [String: Any] else {
            throw HookInstallerError.invalidJSON
        }
        return settings
    }

    /// Backs the current file up to `settings.json.tidewatch-backup`, then writes atomically. A
    /// symlinked settings file is written at its target, so the link survives.
    static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        let fileManager = FileManager.default
        let target = url.resolvingSymlinksInPath()
        if fileManager.fileExists(atPath: target.path) {
            let backup = URL(fileURLWithPath: url.path + ".tidewatch-backup")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: target, to: backup)
        } else {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
    }

    static func connect(settingsURL: URL, helperPath: String) throws {
        let current = try readSettings(at: settingsURL)
        try writeSettings(installing(into: current, helperPath: helperPath), to: settingsURL)
    }

    static func disconnect(settingsURL: URL) throws {
        let current = try readSettings(at: settingsURL)
        let next = removing(from: current)
        guard !NSDictionary(dictionary: next).isEqual(to: current) else { return }
        try writeSettings(next, to: settingsURL)
    }
}
