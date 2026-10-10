import CoreGraphics

/// Geometry of the widget canvas in points, origin bottom left (AppKit). The SwiftUI layout and
/// the hover hit tests both read it, so they always agree.
struct WidgetMetrics: Equatable, Sendable {
    static let canvas = CGSize(width: 340, height: 600)
    static let edgeGap: CGFloat = 8
    static let columnWidth: CGFloat = 36
    static let columnPadding: CGFloat = 9
    static let lampPitch: CGFloat = 26
    static let lampSize: CGFloat = 12
    static let chevronHeight: CGFloat = 16
    static let maxLamps = 6
    static let panelGap: CGFloat = 10
    static let panelWidth: CGFloat = 280
    static let headerHeight: CGFloat = 52
    static let rowHeight: CGFloat = 50
    static let panelBottomPadding: CGFloat = 8
    static let maxVisibleRows = 8
    static let emptyStateHeight: CGFloat = 96
    static let hoverSlop: CGFloat = 8
    static let expandDelay: Duration = .milliseconds(280)
    static let collapseDelay: Duration = .milliseconds(450)
    static let pointerPoll: Duration = .milliseconds(150)

    let sessionCount: Int

    /// No sessions still shows one dim lamp.
    var visibleLamps: Int { min(max(sessionCount, 1), Self.maxLamps) }
    var hasOverflow: Bool { sessionCount > Self.maxLamps }
    var visibleRows: Int { min(sessionCount, Self.maxVisibleRows) }

    var columnRect: CGRect {
        let height = CGFloat(visibleLamps) * Self.lampPitch + 2 * Self.columnPadding + (hasOverflow ? Self.chevronHeight : 0)
        return CGRect(
            x: Self.canvas.width - Self.edgeGap - Self.columnWidth,
            y: ((Self.canvas.height - height) / 2).rounded(),
            width: Self.columnWidth,
            height: height
        )
    }

    var panelRect: CGRect {
        let body = sessionCount == 0 ? Self.emptyStateHeight : CGFloat(visibleRows) * Self.rowHeight
        let height = Self.headerHeight + body + Self.panelBottomPadding
        return CGRect(
            x: columnRect.minX - Self.panelGap - Self.panelWidth,
            y: ((Self.canvas.height - height) / 2).rounded(),
            width: Self.panelWidth,
            height: height
        )
    }

    func lampCenter(_ index: Int) -> CGPoint {
        let top = columnRect.maxY - Self.columnPadding
        return CGPoint(x: columnRect.midX, y: top - (CGFloat(index) + 0.5) * Self.lampPitch)
    }

    func lampIndex(at point: CGPoint) -> Int? {
        guard sessionCount > 0, columnRect.contains(point) else { return nil }
        let top = columnRect.maxY - Self.columnPadding
        let index = Int(((top - point.y) / Self.lampPitch).rounded(.down))
        return (0..<min(sessionCount, Self.maxLamps)).contains(index) ? index : nil
    }

    func rowRect(_ index: Int) -> CGRect {
        let top = panelRect.maxY - Self.headerHeight
        return CGRect(x: panelRect.minX, y: top - CGFloat(index + 1) * Self.rowHeight, width: panelRect.width, height: Self.rowHeight)
    }

    /// Row under the point; nil when the list scrolls (rows no longer sit at fixed places).
    func rowIndex(at point: CGPoint) -> Int? {
        guard sessionCount <= Self.maxVisibleRows else { return nil }
        return (0..<sessionCount).first { rowRect($0).contains(point) }
    }

    /// While expanded, the bounding box of column + panel, so crossing the gap keeps it open.
    func hoverRect(expanded: Bool) -> CGRect {
        let base = expanded ? columnRect.union(panelRect) : columnRect
        return base.insetBy(dx: -Self.hoverSlop, dy: -Self.hoverSlop)
    }

    /// Canvas origin: glued to the right edge of the visible frame, centred vertically.
    static func canvasOrigin(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.maxX - canvas.width, y: (visibleFrame.midY - canvas.height / 2).rounded())
    }
}
