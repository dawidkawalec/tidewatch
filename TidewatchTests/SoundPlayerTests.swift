import Foundation
import Testing
import TidewatchCore
@testable import Tidewatch

@MainActor
struct SoundPlayerTests {
    final class Recorder {
        var now = Date(timeIntervalSince1970: 1_791_620_000)
        var played: [SoundPlayer.Cue] = []
    }

    private func make(_ recorder: Recorder) -> SoundPlayer {
        SoundPlayer(clock: { recorder.now }, play: { recorder.played.append($0) })
    }

    private func transition(_ to: SessionStatus) -> SessionTransition {
        SessionTransition(sessionId: "a", from: .working, to: to)
    }

    @Test func mapsTransitionsToCues() {
        #expect(SoundPlayer.cue(for: transition(.needsApproval)) == .approval)
        #expect(SoundPlayer.cue(for: transition(.awaitingReview)) == .done)
        #expect(SoundPlayer.cue(for: transition(.working)) == nil)
        #expect(SoundPlayer.cue(for: transition(.idle)) == nil)
    }

    @Test func silentRightAfterLaunch() {
        let recorder = Recorder()
        let player = make(recorder)
        recorder.now = recorder.now.addingTimeInterval(1)
        #expect(!player.handle(transition(.needsApproval), enabled: true))
        recorder.now = recorder.now.addingTimeInterval(3)
        #expect(player.handle(transition(.needsApproval), enabled: true))
        #expect(recorder.played == [.approval])
    }

    @Test func atMostOneSoundEveryTwoSeconds() {
        let recorder = Recorder()
        let player = make(recorder)
        recorder.now = recorder.now.addingTimeInterval(10)
        #expect(player.handle(transition(.needsApproval), enabled: true))
        recorder.now = recorder.now.addingTimeInterval(1)
        #expect(!player.handle(transition(.awaitingReview), enabled: true))
        recorder.now = recorder.now.addingTimeInterval(1.5)
        #expect(player.handle(transition(.awaitingReview), enabled: true))
        #expect(recorder.played == [.approval, .done])
    }

    @Test func disabledPlaysNothing() {
        let recorder = Recorder()
        let player = make(recorder)
        recorder.now = recorder.now.addingTimeInterval(10)
        #expect(!player.handle(transition(.needsApproval), enabled: false))
        #expect(recorder.played.isEmpty)
    }
}
