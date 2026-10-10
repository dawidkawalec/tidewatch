import Observation

@MainActor
@Observable
final class WidgetModel {
    var isExpanded = false
    /// Design preview: stays expanded, hover is ignored.
    var isExpansionPinned = false
    /// Lamp or row under the pointer (the same index in both).
    var hoveredIndex: Int?
}
