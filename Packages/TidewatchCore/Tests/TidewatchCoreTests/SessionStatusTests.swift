import Testing
@testable import TidewatchCore

struct SessionStatusTests {
    @Test func rawValuesAreStableForTheStateFile() {
        #expect(SessionStatus.needsApproval.rawValue == "needsApproval")
        #expect(SessionStatus.awaitingReview.rawValue == "awaitingReview")
        #expect(SessionHost.vscode.rawValue == "vscode")
    }
}
