import Foundation
import Testing
import TidewatchCore
@testable import Tidewatch

/// The `widget-demo` preview is recorded into looping videos for the download page, so one cycle
/// has to end exactly where it started.
@MainActor
struct DesignPreviewDemoTests {
    typealias Demo = DesignPreview.Demo

    @Test func stepsAreOrderedWithinOnePeriod() {
        let times = Demo.steps.map(\.at)
        #expect(times == times.sorted())
        #expect(times.allSatisfy { $0 > 0 && $0 < Demo.period })
    }

    @Test func oneCycleEndsWhereItStarted() {
        let end = Demo.steps.reduce(Demo.initial) { $0.applying($1.change) }
        #expect(end == Demo.initial)
    }

    @Test func theCycleShowsTheListAndAnApproval() {
        var scene = Demo.initial
        var sawExpanded = false
        var sawApproval = false
        for step in Demo.steps {
            scene = scene.applying(step.change)
            sawExpanded = sawExpanded || scene.expanded
            sawApproval = sawApproval || scene.lamps.contains { $0.status == .needsApproval }
        }
        #expect(sawExpanded)
        #expect(sawApproval)
    }

    /// The video shows a VS Code window with two tabs and conversation titles.
    @Test func theDemoHasAWindowWithTwoTabsAndTitles() {
        let sessions = Demo.sessions(for: Demo.initial, now: Date())
        let windows = DesignPreview.windows(for: sessions)
        let omnira = sessions.filter { $0.project == "Omnira" }.compactMap { $0.pid.flatMap { windows[$0] } }
        #expect(omnira.count == 2)
        #expect(Set(omnira).count == 1)
        #expect(sessions.allSatisfy { $0.title != nil })
    }

    @Test func sessionsFollowTheScene() {
        let now = Date(timeIntervalSince1970: 1_791_620_000)
        let scene = Demo.initial.applying(.appear(Demo.Lamp(order: 2, name: "Zorko", status: .working, activity: .coding)))
        let sessions = Demo.sessions(for: scene, now: now)
        #expect(sessions.map(\.project) == scene.lamps.map(\.name))
        #expect(sessions.first { $0.project == "Zorko" }?.status == .working)
    }
}
