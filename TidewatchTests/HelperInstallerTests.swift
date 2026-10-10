import Foundation
import Testing
@testable import Tidewatch

struct HelperInstallerTests {
    private func makeSource(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tw-src-\(UUID().uuidString)")
        try Data(content.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func copiesOnceThenOnlyWhenChanged() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("tw-dst-\(UUID().uuidString)/bin/tidewatch-hook")
        let source = try makeSource("v1")
        #expect(try HelperInstaller.refresh(from: source, to: destination))
        #expect(FileManager.default.isExecutableFile(atPath: destination.path))
        #expect(try !HelperInstaller.refresh(from: source, to: destination))
        let updated = try makeSource("v2")
        #expect(try HelperInstaller.refresh(from: updated, to: destination))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "v2")
    }

    @Test func missingSourceThrows() {
        #expect(throws: HelperInstallerError.missingBundledHelper) {
            try HelperInstaller.refresh(from: nil, to: URL(fileURLWithPath: "/tmp/x"))
        }
    }

    @Test func bundledHelperSitsNextToTheExecutable() throws {
        let helper = try #require(HelperInstaller.bundledHelper())
        #expect(helper.lastPathComponent == "tidewatch-hook")
        #expect(helper.deletingLastPathComponent().lastPathComponent == "MacOS")
    }
}
