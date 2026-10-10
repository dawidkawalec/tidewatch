import Foundation
import Testing
@testable import TidewatchCore

struct HookEventTests {
    private func decode(_ json: String) throws -> HookEvent {
        try HookEvent.decode(Data(json.utf8))
    }

    @Test func decodesPreToolUseWithBashCommand() throws {
        let event = try decode(#"{"session_id":"s1","transcript_path":"/x.jsonl","cwd":"/Users/demo/app","permission_mode":"auto","effort":{"level":"high"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"},"tool_use_id":"t1"}"#)
        #expect(event.kind == .preToolUse)
        #expect(event.rawName == "PreToolUse")
        #expect(event.sessionId == "s1")
        #expect(event.cwd == "/Users/demo/app")
        #expect(event.toolName == "Bash")
        #expect(event.command == "npm test")
        #expect(event.filePath == nil)
    }

    @Test func decodesFilePathAndSkipsToolResponse() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/Users/demo/app","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"/Users/demo/app/src/a.swift","old_string":"a","new_string":"b"},"tool_response":{"filePath":"/x","structuredPatch":[{"lines":["-a","+b"]}]},"duration_ms":4}"#)
        #expect(event.kind == .postToolUse)
        #expect(event.filePath == "/Users/demo/app/src/a.swift")
    }

    @Test func countsOnlyRunningBackgroundTasks() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[{"id":"a","type":"shell","status":"running"},{"id":"b","status":"completed"},{"id":"c","status":"running"}]}"#)
        #expect(event.kind == .stop)
        #expect(event.runningBackgroundTasks == 2)
    }

    @Test func decodesNotificationTypeAndMessage() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}"#)
        #expect(event.kind == .notification)
        #expect(event.notificationType == "permission_prompt")
        #expect(event.message == "Claude needs your permission to use Bash")
    }

    @Test func decodesSessionTitle() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"SessionStart","source":"startup","session_title":"Fix login form"}"#)
        #expect(event.kind == .sessionStart)
        #expect(event.sessionTitle == "Fix login form")
    }

    @Test func unknownEventNameHasNoKind() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"FileChanged"}"#)
        #expect(event.kind == nil)
        #expect(event.rawName == "FileChanged")
    }

    @Test func toolInputOfAnotherShapeIsTolerated() throws {
        let numeric = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":42}}"#)
        #expect(numeric.command == nil)
        let string = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"PreToolUse","tool_name":"X","tool_input":"raw"}"#)
        #expect(string.toolName == "X")
    }

    @Test func missingCwdBecomesEmpty() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Stop"}"#)
        #expect(event.cwd == "")
    }

    @Test func missingSessionIdOrGarbageThrows() {
        #expect(throws: (any Error).self) { try decode(#"{"hook_event_name":"Stop"}"#) }
        #expect(throws: (any Error).self) { try decode("not json") }
        #expect(throws: (any Error).self) { try decode("") }
    }
}
