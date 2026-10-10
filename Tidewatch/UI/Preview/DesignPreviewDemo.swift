import AppKit
import SwiftUI
import TidewatchCore

/// `--design-preview widget-demo`: a scripted cycle for the download page's looping videos
/// (scripts/record-demo.sh). A session appears, asks for approval, the list wells out, a row is
/// hovered, the list closes and everything returns to the first frame, so any one period of the
/// recording loops without a seam.
extension DesignPreview {
    @MainActor
    enum Demo {
        struct Lamp: Equatable {
            var order: Int
            var name: String
            var status: SessionStatus
            var activity: SessionActivity
            var tool: String?
            var detail: String?
        }

        struct Scene: Equatable {
            var lamps: [Lamp]
            var expanded = false
            var hovered: Int?

            func applying(_ change: Change) -> Scene {
                var next = self
                switch change {
                case .appear(let lamp):
                    next.lamps.removeAll { $0.name == lamp.name }
                    next.lamps.append(lamp)
                    next.lamps.sort { $0.order < $1.order }
                case let .update(name, status, activity, tool, detail):
                    if let index = next.lamps.firstIndex(where: { $0.name == name }) {
                        next.lamps[index].status = status
                        next.lamps[index].activity = activity
                        next.lamps[index].tool = tool
                        next.lamps[index].detail = detail
                    }
                case .remove(let name):
                    next.lamps.removeAll { $0.name == name }
                case .expand(let expanded):
                    next.expanded = expanded
                case .hover(let index):
                    next.hovered = index
                }
                return next
            }
        }

        enum Change: Equatable {
            case appear(Lamp)
            case update(name: String, status: SessionStatus, activity: SessionActivity = .working, tool: String? = nil, detail: String? = nil)
            case remove(String)
            case expand(Bool)
            case hover(Int?)
        }

        struct Step {
            let at: TimeInterval
            let change: Change
        }

        static let period: TimeInterval = 12

        static let initial = Scene(lamps: [
            Lamp(order: 1, name: "Captylo", status: .working, activity: .coding),
            Lamp(order: 3, name: "Omnira", status: .working, activity: .runningTests),
            Lamp(order: 4, name: "Craftweb", status: .idle, activity: .working),
            Lamp(order: 5, name: "Blog AI", status: .working, activity: .researching),
        ])

        static let steps: [Step] = [
            Step(at: 1.2, change: .appear(Lamp(order: 2, name: "Zorko", status: .working, activity: .coding))),
            Step(at: 2.6, change: .update(name: "Zorko", status: .needsApproval, tool: "Bash", detail: "npm install")),
            Step(at: 4.0, change: .expand(true)),
            Step(at: 5.3, change: .hover(1)),
            Step(at: 6.5, change: .hover(nil)),
            Step(at: 7.1, change: .update(name: "Captylo", status: .awaitingReview)),
            Step(at: 8.6, change: .expand(false)),
            Step(at: 9.5, change: .update(name: "Zorko", status: .working, activity: .coding)),
            Step(at: 10.3, change: .remove("Zorko")),
            Step(at: 10.9, change: .update(name: "Captylo", status: .working, activity: .coding)),
        ]

        static func sessions(for scene: Scene, now: Date) -> [SessionState] {
            scene.lamps.map { lamp in
                var state = SessionState(sessionId: "demo-\(lamp.order)", cwd: "/Users/demo/\(lamp.name)", host: .vscode, terminalApp: nil, pid: nil, now: now)
                state.startedConversation = true
                state.status = lamp.status
                state.activity = lamp.activity
                state.tool = lamp.tool
                state.detail = lamp.detail
                state.statusSince = now.addingTimeInterval(-Double(lamp.order * 2) * 60)
                state.firstSeen = now.addingTimeInterval(-Double(100 - lamp.order) * 60)
                return state
            }
        }

        /// Plays the cycle forever. Steps are scheduled against the start time, so the period does
        /// not drift over a long recording.
        static func play(store: SessionStore, files: SessionFileStore, model: WidgetModel) {
            var scene = initial
            let start = Date()
            show(scene, store: store, files: files, model: model, animated: false)
            // record-demo.sh cuts its window from the start of a cycle.
            print("DEMO_START=\(start.timeIntervalSince1970)")
            print("DEMO_PERIOD=\(period)")
            fflush(stdout)
            Task { @MainActor in
                var cycle = 0
                while !Task.isCancelled {
                    for step in steps {
                        let due = start.addingTimeInterval(Double(cycle) * period + step.at)
                        let wait = due.timeIntervalSinceNow
                        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                        scene = scene.applying(step.change)
                        show(scene, store: store, files: files, model: model, animated: true)
                    }
                    cycle += 1
                }
            }
        }

        private static func show(_ scene: Scene, store: SessionStore, files: SessionFileStore, model: WidgetModel, animated: Bool) {
            let now = Date()
            let sessions = sessions(for: scene, now: now)
            let keep = Set(sessions.map(\.sessionId))
            for state in files.loadAll() where !keep.contains(state.sessionId) {
                files.remove(sessionId: state.sessionId)
            }
            for state in sessions {
                try? files.write(state, to: files.fileURL(for: state.sessionId))
            }
            if animated {
                withAnimation(GlassMotion.liquid) { apply(scene, store: store, model: model) }
            } else {
                apply(scene, store: store, model: model)
            }
        }

        private static func apply(_ scene: Scene, store: SessionStore, model: WidgetModel) {
            store.reload()
            model.isExpanded = scene.expanded
            model.hoveredIndex = scene.hovered
        }
    }
}
