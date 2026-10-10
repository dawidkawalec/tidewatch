import Foundation
import Testing
@testable import TidewatchCore

struct SessionFileStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func makeStore() -> SessionFileStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tw-store-\(UUID().uuidString)/sessions", isDirectory: true)
        return SessionFileStore(directory: dir)
    }

    private func context(_ s: TimeInterval = 0) -> EventContext {
        EventContext(now: t0.addingTimeInterval(s), host: .vscode, terminalApp: nil, pid: 42)
    }

    private func event(_ kind: HookEvent.Kind, id: String = "s-1") -> HookEvent {
        HookEvent(kind: kind, sessionId: id, cwd: "/Users/demo/app")
    }

    @Test func applyWritesAndUpdatesTheFile() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart), context: context())
        try store.apply(event(.userPromptSubmit), context: context(1))
        let state = try #require(store.read(store.fileURL(for: "s-1")))
        #expect(state.status == .working)
        #expect(state.firstSeen == t0)
        #expect(store.loadAll().map(\.sessionId) == ["s-1"])
    }

    @Test func sessionEndDeletesFileAndLock() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart), context: context())
        try store.apply(event(.sessionEnd), context: context(1))
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.isEmpty)
    }

    @Test func rejectsPathTraversal() throws {
        let store = makeStore()
        #expect(throws: SessionFileStoreError.invalidSessionId("../evil")) {
            try store.apply(event(.stop, id: "../evil"), context: context())
        }
        #expect(!FileManager.default.fileExists(atPath: store.directory.deletingLastPathComponent().appendingPathComponent("evil.json").path))
        #expect(!SessionFileStore.isValidSessionId(""))
        #expect(!SessionFileStore.isValidSessionId("a/b"))
        #expect(SessionFileStore.isValidSessionId("2c7f6edd-2153-4800-a181-b41e70f4f557"))
    }

    @Test func ignoredEventsWriteNothing() throws {
        let store = makeStore()
        var unknown = event(.stop)
        unknown.kind = nil
        #expect(try store.apply(unknown, context: context()) == .ignore)
        #expect(store.loadAll().isEmpty)
    }

    @Test func loadAllSkipsCorruptAndForeignFiles() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart, id: "good"), context: context())
        try Data("{ half".utf8).write(to: store.directory.appendingPathComponent("bad.json"))
        try Data("x".utf8).write(to: store.directory.appendingPathComponent("notes.txt"))
        #expect(store.loadAll().map(\.sessionId) == ["good"])
    }

    @Test func removeDeletesOneSession() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart, id: "a"), context: context())
        try store.apply(event(.sessionStart, id: "b"), context: context())
        store.remove(sessionId: "a")
        #expect(store.loadAll().map(\.sessionId) == ["b"])
    }

    @Test func concurrentAppliesLeaveAValidFile() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart), context: context())
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let kind: HookEvent.Kind = index.isMultiple(of: 2) ? .preToolUse : .postToolUse
            _ = try? store.apply(HookEvent(kind: kind, sessionId: "s-1", cwd: "/Users/demo/app", toolName: "Read", filePath: "/a"), context: context(Double(index)))
        }
        let state = try #require(store.read(store.fileURL(for: "s-1")))
        #expect(state.status == .working)
    }
}
