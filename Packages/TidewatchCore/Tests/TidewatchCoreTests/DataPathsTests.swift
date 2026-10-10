import Foundation
import Testing
@testable import TidewatchCore

struct DataPathsTests {
    @Test func defaultsToApplicationSupport() {
        let root = DataPaths.root(environment: [:])
        #expect(root.path.hasSuffix("/Library/Application Support/Tidewatch"))
        #expect(DataPaths.sessions(environment: [:]).path.hasSuffix("/Tidewatch/sessions"))
        #expect(DataPaths.helper(environment: [:]).path.hasSuffix("/Tidewatch/bin/tidewatch-hook"))
    }

    @Test func environmentOverridesTheRoot() {
        let env = ["TIDEWATCH_DATA_DIR": "/tmp/tw-test"]
        #expect(DataPaths.root(environment: env).path == "/tmp/tw-test")
        #expect(DataPaths.sessions(environment: env).path == "/tmp/tw-test/sessions")
    }
}
