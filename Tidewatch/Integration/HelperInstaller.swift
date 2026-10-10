import Foundation

enum HelperInstallerError: Error, Equatable {
    case missingBundledHelper
}

/// Keeps a stable copy of the hook helper in Application Support, so the command path stored in
/// settings.json survives moving or updating the app (spec 3).
enum HelperInstaller {
    /// `Tidewatch.app/Contents/MacOS/tidewatch-hook`.
    static func bundledHelper(in bundle: Bundle = .main) -> URL? {
        bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("tidewatch-hook")
    }

    /// Copies `source` to `destination` when they differ. Returns true when it copied.
    @discardableResult
    static func refresh(from source: URL?, to destination: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard let source, fileManager.isExecutableFile(atPath: source.path) else {
            throw HelperInstallerError.missingBundledHelper
        }
        if fileManager.contentsEqual(atPath: source.path, andPath: destination.path) { return false }
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".tidewatch-hook.\(UUID().uuidString)")
        try fileManager.copyItem(at: source, to: temporary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        // rename(2) replaces the old copy atomically: a hook running right now sees either one.
        guard rename(temporary.path, destination.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
        return true
    }
}
