import Testing
@testable import TidewatchCore

struct ApprovalDetailTests {
    private func event(_ tool: String, command: String? = nil, filePath: String? = nil, url: String? = nil) -> HookEvent {
        HookEvent(kind: .permissionRequest, sessionId: "s", cwd: "/Users/demo/app", toolName: tool, command: command, filePath: filePath, url: url)
    }

    @Test func bashShowsTheFirstLineShortened() {
        #expect(ApprovalDetail.describe(event("Bash", command: "npm install\nnpm test")) == "npm install")
        let long = String(repeating: "a", count: 100)
        let detail = ApprovalDetail.describe(event("Bash", command: long))
        #expect(detail?.count == 60)
        #expect(detail?.hasSuffix("…") == true)
    }

    @Test func fileToolsShowTheFileName() {
        #expect(ApprovalDetail.describe(event("Edit", filePath: "/Users/demo/app/src/Hero.tsx")) == "Hero.tsx")
        #expect(ApprovalDetail.describe(event("Write", filePath: "/Users/demo/app/README.md")) == "README.md")
    }

    @Test func webFetchShowsTheHost() {
        #expect(ApprovalDetail.describe(event("WebFetch", url: "https://docs.example.com/a/b")) == "docs.example.com")
    }

    @Test func questionsAndMissingInputHaveNoDetail() {
        #expect(ApprovalDetail.describe(event("AskUserQuestion")) == nil)
        #expect(ApprovalDetail.describe(event("Bash")) == nil)
        #expect(ApprovalDetail.describe(HookEvent(kind: .permissionRequest, sessionId: "s", cwd: "/a")) == nil)
    }

    @Test func mcpToolsShowTheToolPart() {
        #expect(ApprovalDetail.describe(event("mcp__plane__create_work_item")) == "create_work_item")
        #expect(ApprovalDetail.describe(event("TodoWrite")) == "TodoWrite")
    }

    @Test func signatureMatchesTheSameCallOnly() {
        #expect(ApprovalDetail.signature(event("Bash", command: "npm install")) == ApprovalDetail.signature(HookEvent(kind: .postToolUse, sessionId: "s", cwd: "/a", toolName: "Bash", command: "npm install")))
        #expect(ApprovalDetail.signature(event("Bash", command: "npm install")) != ApprovalDetail.signature(event("Bash", command: "npm test")))
        #expect(ApprovalDetail.signature(event("Read", filePath: "/a")) != ApprovalDetail.signature(event("Edit", filePath: "/a")))
    }
}
