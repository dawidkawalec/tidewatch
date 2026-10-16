import CoreGraphics
import Observation

@MainActor
@Observable
final class WidgetModel {
    var isExpanded = false
    /// Design preview: stays expanded, hover is ignored.
    var isExpansionPinned = false
    /// Lamp or row under the pointer (the same index in both).
    var hoveredIndex: Int?
    /// How far the session list is scrolled up (`WidgetMetrics.maxScroll` at most).
    var scrollOffset: CGFloat = 0
    /// The canvas window's height: the screen's visible height (the preview keeps 600).
    var canvasHeight: CGFloat = WidgetMetrics.defaultCanvasHeight
}
