import Testing
@testable import TidewatchCore

struct ActivityClassifierTests {
    @Test(arguments: [
        "npm test", "npm run test", "pnpm test -- --watch=false", "yarn test", "bun test",
        "make test", "swift test --package-path Packages/Core", "cargo test", "go test ./...",
        "xcodebuild -scheme App -destination 'platform=macOS' test", "npx vitest run", "pytest -q",
        "jest src", "npx playwright test", "cd app && npm test",
    ])
    func recognisesTestCommands(_ command: String) {
        #expect(ActivityClassifier.isTestCommand(command))
        #expect(ActivityClassifier.activity(forTool: "Bash", command: command) == .runningTests)
    }

    @Test(arguments: [
        "touch /tmp/test.txt", "cat src/test/a.swift", "go build && ls test", "git commit -m 'add tests'",
        "npm install", "ls -la",
    ])
    func otherCommandsAreJustCommands(_ command: String) {
        #expect(!ActivityClassifier.isTestCommand(command))
        #expect(ActivityClassifier.activity(forTool: "Bash", command: command) == .runningCommands)
    }

    @Test func mapsToolsToActivities() {
        #expect(ActivityClassifier.activity(forTool: "Edit", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "Write", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "MultiEdit", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "NotebookEdit", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "Read", command: nil) == .readingCode)
        #expect(ActivityClassifier.activity(forTool: "Grep", command: nil) == .readingCode)
        #expect(ActivityClassifier.activity(forTool: "Glob", command: nil) == .readingCode)
        #expect(ActivityClassifier.activity(forTool: "WebSearch", command: nil) == .researching)
        #expect(ActivityClassifier.activity(forTool: "WebFetch", command: nil) == .researching)
        #expect(ActivityClassifier.activity(forTool: "Task", command: nil) == .runningAgents)
        #expect(ActivityClassifier.activity(forTool: "Agent", command: nil) == .runningAgents)
        #expect(ActivityClassifier.activity(forTool: "mcp__plane__list_projects", command: nil) == .usingTools)
        #expect(ActivityClassifier.activity(forTool: "TodoWrite", command: nil) == .working)
        #expect(ActivityClassifier.activity(forTool: "Bash", command: nil) == .runningCommands)
    }
}
