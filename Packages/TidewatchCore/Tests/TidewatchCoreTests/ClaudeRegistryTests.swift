import Foundation
import Testing
@testable import TidewatchCore

/// Claude Code lists every running process in `~/.claude/sessions/<pid>.json`. Tidewatch reads it
/// to know all open sessions, also the ones that fired no hook since Tidewatch started.
struct ClaudeRegistryTests {
    private let sample = #"""
    {"pid":4835,"sessionId":"10c4e175-05e6-463b-a6b8-d8306b2fe8c9","cwd":"/Users/demo/atlas","startedAt":1791577512185,
     "procStart":"Fri Oct  9 20:25:11 2026","version":"2.1.292","kind":"interactive","entrypoint":"claude-vscode",
     "name":"atlas-d7","status":"waiting","updatedAt":1791661279920,"statusUpdatedAt":1791661279000,"waitingFor":"input needed"}
    """#

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tw-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func decodesARegistryFile() throws {
        let process = try #require(ClaudeRegistry.decode(Data(sample.utf8)))
        #expect(process.pid == 4835)
        #expect(process.sessionId == "10c4e175-05e6-463b-a6b8-d8306b2fe8c9")
        #expect(process.cwd == "/Users/demo/atlas")
        #expect(process.entrypoint == "claude-vscode")
        #expect(process.kind == "interactive")
        #expect(process.status == "waiting")
        #expect(process.waitingFor == "input needed")
        #expect(process.startedAt == Date(timeIntervalSince1970: 1_791_577_512.185))
        #expect(process.statusUpdatedAt == Date(timeIntervalSince1970: 1_791_661_279))
    }

    @Test func refusesFilesWithoutTheEssentials() {
        #expect(ClaudeRegistry.decode(Data(#"{"pid":1,"cwd":"/x"}"#.utf8)) == nil)
        #expect(ClaudeRegistry.decode(Data(#"{"pid":1,"sessionId":"../../etc","cwd":"/x","startedAt":1}"#.utf8)) == nil)
        #expect(ClaudeRegistry.decode(Data("not json".utf8)) == nil)
    }

    @Test func loadsOnlyTheJSONFilesOfAFolder() throws {
        let dir = try folder()
        try Data(sample.utf8).write(to: dir.appendingPathComponent("4835.json"))
        try Data("secret".utf8).write(to: dir.appendingPathComponent("4835.abc.key"))
        try Data("{broken".utf8).write(to: dir.appendingPathComponent("77.json"))
        let processes = ClaudeRegistry.load(directory: dir)
        #expect(processes.map(\.pid) == [4835])
        #expect(ClaudeRegistry.load(directory: dir.appendingPathComponent("missing")).isEmpty)
    }

    @Test func registryFolderFollowsClaudeConfigDir() {
        #expect(ClaudeRegistry.configDirectory(home: "/Users/demo", environment: [:]).path == "/Users/demo/.claude")
        #expect(ClaudeRegistry.configDirectory(home: "/Users/demo", environment: ["CLAUDE_CONFIG_DIR": "/tmp/cc"]).path == "/tmp/cc")
        #expect(ClaudeRegistry.sessionsDirectory(config: URL(fileURLWithPath: "/Users/demo/.claude")).path == "/Users/demo/.claude/sessions")
    }

    @Test func transcriptPathUsesClaudeCodesFolderNames() {
        #expect(ClaudeRegistry.projectSlug("/Users/demo/projects/site_all-copy") == "-Users-demo-projects-site-all-copy")
        #expect(ClaudeRegistry.projectSlug("/Users/demo/Local Sites/shop") == "-Users-demo-Local-Sites-shop")
        let url = ClaudeRegistry.transcriptURL(config: URL(fileURLWithPath: "/Users/demo/.claude"), cwd: "/Users/demo/app", sessionId: "s-1")
        #expect(url.path == "/Users/demo/.claude/projects/-Users-demo-app/s-1.jsonl")
    }

    @Test func titleIsTheLastAITitleOfTheTranscript() {
        let tail = """
        ant","message":{"content":"half a line"}}
        {"type":"ai-title","aiTitle":"First idea","sessionId":"s"}
        {"type":"user","message":{"content":"{\\"type\\":\\"ai-title\\",\\"aiTitle\\":\\"quoted\\"}"}}
        {"type":"ai-title","aiTitle":"Checkout redesign","sessionId":"s"}
        {"type":"assistant","message":{"content":"ok"}}
        """
        #expect(ClaudeRegistry.title(inTranscriptTail: Data(tail.utf8)) == "Checkout redesign")
    }

    @Test func aTitleTheUserGaveWinsOverTheGeneratedOne() {
        let tail = """
        {"type":"custom-title","customTitle":"Release 0.4","sessionId":"s"}
        {"type":"ai-title","aiTitle":"Generated","sessionId":"s"}
        """
        #expect(ClaudeRegistry.title(inTranscriptTail: Data(tail.utf8)) == "Release 0.4")
    }

    @Test func noTitleInATranscriptWithoutOne() {
        #expect(ClaudeRegistry.title(inTranscriptTail: Data(#"{"type":"user"}"#.utf8)) == nil)
        #expect(ClaudeRegistry.title(inTranscriptTail: Data()) == nil)
        #expect(ClaudeRegistry.title(inTranscriptTail: Data(#"{"type":"ai-title","aiTitle":"  "}"#.utf8)) == nil)
    }
}
