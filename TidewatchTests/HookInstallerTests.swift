import Foundation
import Testing
@testable import Tidewatch

struct HookInstallerTests {
    private let helper = "/Users/demo/Library/Application Support/Tidewatch/bin/tidewatch-hook"

    private func tempURL(_ name: String = "settings.json") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tw-hooks-\(UUID().uuidString)").appendingPathComponent(name)
    }

    private func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    @Test func installsEveryEventWithQuotedCommandAndTimeout() throws {
        let result = HookInstaller.installing(into: [:], helperPath: helper)
        let hooks = try #require(result["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.events.map(\.name)))
        let pre = try #require((hooks["PreToolUse"] as? [Any])?.first as? [String: Any])
        #expect(pre["matcher"] as? String == "*")
        let entry = try #require((pre["hooks"] as? [Any])?.first as? [String: Any])
        #expect(entry["type"] as? String == "command")
        #expect(entry["command"] as? String == "\"\(helper)\"")
        #expect(entry["timeout"] as? Int == 5)
        let stop = try #require((hooks["Stop"] as? [Any])?.first as? [String: Any])
        #expect(stop["matcher"] == nil)
        #expect(HookInstaller.isInstalled(result, helperPath: helper))
    }

    @Test func keepsOtherKeysAndOtherHooks() throws {
        let settings = json(#"{"effortLevel":"high","remoteControlAtStartup":true,"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard"}]}],"Stop":[]}}"#)
        let installed = HookInstaller.installing(into: settings, helperPath: helper)
        #expect(installed["effortLevel"] as? String == "high")
        #expect(installed["remoteControlAtStartup"] as? Bool == true)
        let pre = try #require((installed["hooks"] as? [String: Any])?["PreToolUse"] as? [Any])
        #expect(pre.count == 2)
        #expect(!HookInstaller.isTidewatchGroup(pre[0]))
        #expect(HookInstaller.isTidewatchGroup(pre[1]))

        let removed = HookInstaller.removing(from: installed)
        let hooks = try #require(removed["hooks"] as? [String: Any])
        #expect((hooks["PreToolUse"] as? [Any])?.count == 1)
        // An event array left empty after removing Tidewatch is dropped: for Claude Code an empty
        // array and a missing key are the same (Task 7 ruling in the ledger).
        #expect(hooks["Stop"] == nil)
        #expect(hooks["SessionStart"] == nil)
        #expect(!HookInstaller.isInstalled(removed, helperPath: helper))
    }

    @Test func installingTwiceDoesNotDuplicate() throws {
        let twice = HookInstaller.installing(into: HookInstaller.installing(into: [:], helperPath: helper), helperPath: helper)
        let stop = try #require((twice["hooks"] as? [String: Any])?["Stop"] as? [Any])
        #expect(stop.count == 1)
    }

    @Test func reinstallingWithANewPathReplacesTheOldEntries() throws {
        let old = HookInstaller.installing(into: [:], helperPath: "/Old/Tidewatch/bin/tidewatch-hook")
        let new = HookInstaller.installing(into: old, helperPath: helper)
        #expect(HookInstaller.isInstalled(new, helperPath: helper))
        #expect(!HookInstaller.isInstalled(new, helperPath: "/Old/Tidewatch/bin/tidewatch-hook"))
        #expect(((new["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 1)
    }

    @Test func removingFromSettingsWithoutTidewatchChangesNothing() {
        let settings = json(#"{"hooks":{"Stop":[]},"a":1}"#)
        let removed = HookInstaller.removing(from: settings)
        #expect(NSDictionary(dictionary: removed).isEqual(to: settings))
    }

    @Test func connectCreatesAMissingFile() throws {
        let url = tempURL()
        try HookInstaller.connect(settingsURL: url, helperPath: helper)
        #expect(HookInstaller.isInstalled(try HookInstaller.readSettings(at: url), helperPath: helper))
        #expect(!FileManager.default.fileExists(atPath: url.path + ".tidewatch-backup"))
    }

    @Test func connectBacksUpAndPreservesTheFile() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"enabledPlugins":{"x@y":true},"permissions":{"allow":["Bash(ls)"]}}"#
        try Data(original.utf8).write(to: url)
        try HookInstaller.connect(settingsURL: url, helperPath: helper)
        let backup = try String(contentsOf: URL(fileURLWithPath: url.path + ".tidewatch-backup"), encoding: .utf8)
        #expect(backup == original)
        let settings = try HookInstaller.readSettings(at: url)
        #expect((settings["enabledPlugins"] as? [String: Any])?["x@y"] as? Bool == true)
        #expect(((settings["permissions"] as? [String: Any])?["allow"] as? [String]) == ["Bash(ls)"])
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"x@y\" : true"))

        try HookInstaller.disconnect(settingsURL: url)
        #expect(try HookInstaller.readSettings(at: url)["hooks"] == nil)
    }

    @Test func invalidJSONIsNeverOverwritten() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: url)
        #expect(throws: HookInstallerError.invalidJSON) {
            try HookInstaller.connect(settingsURL: url, helperPath: helper)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ broken")
    }

    @Test func writesThroughASymlinkedSettingsFile() throws {
        let real = tempURL("real-settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: real)
        let link = real.deletingLastPathComponent().appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try HookInstaller.connect(settingsURL: link, helperPath: helper)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(HookInstaller.isInstalled(try HookInstaller.readSettings(at: real), helperPath: helper))
    }

    @Test func emptyFileCountsAsEmptySettings() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("  \n".utf8).write(to: url)
        #expect(try HookInstaller.readSettings(at: url).isEmpty)
    }
}
