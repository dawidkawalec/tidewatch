/// What the widget can ask the app to do.
struct WidgetActions {
    var open: @MainActor (DisplayedSession) -> Void
    var showInFinder: @MainActor (DisplayedSession) -> Void
    var connect: @MainActor () -> Void
    var restart: @MainActor () -> Void

    @MainActor static var preview: WidgetActions {
        WidgetActions(open: { _ in }, showInFinder: { _ in }, connect: {}, restart: {})
    }
}
