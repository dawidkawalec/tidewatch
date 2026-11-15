import Foundation
import Testing
import TidewatchCore

struct T3LinkTests {
    @Test func buildsTheThreadURLT3Routes() {
        let url = T3Link.threadURL(environmentId: "00000000-0000-4000-8000-000000000001", threadId: "00000000-0000-4000-8000-000000000002")
        #expect(url?.absoluteString == "t3code://threads/00000000-0000-4000-8000-000000000001/00000000-0000-4000-8000-000000000002")
        #expect(T3Link.threadURL(environmentId: "", threadId: "t") == nil)
        #expect(T3Link.threadURL(environmentId: "e", threadId: "") == nil)
    }

    @Test func findsT3Home() {
        let user = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        #expect(T3Link.home(environment: [:], userHome: user).path == "/Users/demo/.t3")
        #expect(T3Link.home(environment: ["T3CODE_HOME": "/opt/t3"], userHome: user).path == "/opt/t3")
        #expect(T3Link.cli(home: URL(fileURLWithPath: "/Users/demo/.t3")).path == "/Users/demo/.t3/bin/t3")
    }

    @Test func readsTheEnvironmentId() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("t3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(T3Link.environmentId(home: home) == nil)
        let userdata = home.appendingPathComponent("userdata", isDirectory: true)
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        try "env-1\n".write(to: userdata.appendingPathComponent("environment-id"), atomically: true, encoding: .utf8)
        #expect(T3Link.environmentId(home: home) == "env-1")
    }
}
