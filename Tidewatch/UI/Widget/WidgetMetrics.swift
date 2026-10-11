import CoreGraphics

/// Geometry of the widget canvas in points, origin bottom left (AppKit). The SwiftUI layout and
/// the hover hit tests both read it, so they always agree.
///
/// Sessions come in windows (`groupSizes`, in widget order). A window with several tabs is parted
/// from its neighbours by a gap in the column and gets a header in the list; windows with one tab
/// each look like a plain list.
struct WidgetMetrics: Equatable, Sendable {
    static let canvas = CGSize(width: 352, height: 600)
    static let edgeGap: CGFloat = 8
    static let columnWidth: CGFloat = 36
    static let columnPadding: CGFloat = 9
    static let lampPitch: CGFloat = 26
    static let lampSize: CGFloat = 12
    static let groupGap: CGFloat = 10
    static let chevronHeight: CGFloat = 16
    static let maxLamps = 10
    static let panelGap: CGFloat = 16
    static let panelWidth: CGFloat = 280
    static let headerHeight: CGFloat = 52
    static let groupHeaderHeight: CGFloat = 26
    static let rowHeight: CGFloat = 50
    static let panelBottomPadding: CGFloat = 8
    /// The list scrolls past this (eight rows).
    static let maxBodyHeight: CGFloat = 400
    static let emptyStateHeight: CGFloat = 96
    static let hoverSlop: CGFloat = 8
    static let expandDelay: Duration = .milliseconds(280)
    static let collapseDelay: Duration = .milliseconds(450)
    static let pointerPoll: Duration = .milliseconds(150)

    let groupSizes: [Int]
    /// Per session in widget order: whether its window has several tabs, and whether it is the
    /// first of its window.
    private let grouped: [Bool]
    private let opensGroup: [Bool]

    init(groupSizes: [Int]) {
        self.groupSizes = groupSizes.filter { $0 > 0 }
        var grouped: [Bool] = []
        var opensGroup: [Bool] = []
        for size in self.groupSizes {
            for index in 0..<size {
                grouped.append(size > 1)
                opensGroup.append(index == 0)
            }
        }
        self.grouped = grouped
        self.opensGroup = opensGroup
    }

    /// One tab per window.
    init(sessionCount: Int) {
        self.init(groupSizes: Array(repeating: 1, count: max(sessionCount, 0)))
    }

    var sessionCount: Int { grouped.count }

    /// No sessions still shows one dim lamp.
    var visibleLamps: Int { min(max(sessionCount, 1), Self.maxLamps) }
    var hasOverflow: Bool { sessionCount > Self.maxLamps }

    /// A gap above this lamp: it opens a window and this window or the one above has several tabs.
    func gapBefore(_ index: Int) -> Bool {
        guard index > 0, index < sessionCount, opensGroup[index] else { return false }
        return grouped[index] || grouped[index - 1]
    }

    /// A header above this row: it opens a window with several tabs.
    func headerBefore(_ index: Int) -> Bool {
        index >= 0 && index < sessionCount && opensGroup[index] && grouped[index]
    }

    // MARK: Column

    /// Distance from the column's first lamp slot to the top of this lamp's slot.
    private func lampOffset(_ index: Int) -> CGFloat {
        let gaps = (0...max(index, 0)).filter(gapBefore).count
        return CGFloat(index) * Self.lampPitch + CGFloat(gaps) * Self.groupGap
    }

    var columnRect: CGRect {
        let lamps = lampOffset(visibleLamps - 1) + Self.lampPitch
        let height = lamps + 2 * Self.columnPadding + (hasOverflow ? Self.chevronHeight : 0)
        return CGRect(
            x: Self.canvas.width - Self.edgeGap - Self.columnWidth,
            y: ((Self.canvas.height - height) / 2).rounded(),
            width: Self.columnWidth,
            height: height
        )
    }

    func lampCenter(_ index: Int) -> CGPoint {
        let top = columnRect.maxY - Self.columnPadding
        return CGPoint(x: columnRect.midX, y: top - lampOffset(index) - Self.lampPitch / 2)
    }

    func lampIndex(at point: CGPoint) -> Int? {
        guard sessionCount > 0, columnRect.contains(point) else { return nil }
        return (0..<min(sessionCount, Self.maxLamps)).first { abs(lampCenter($0).y - point.y) < Self.lampPitch / 2 }
    }

    // MARK: Panel

    /// Distance from the top of the list to the top of this row.
    private func rowOffset(_ index: Int) -> CGFloat {
        let headers = (0...max(index, 0)).filter(headerBefore).count
        return CGFloat(index) * Self.rowHeight + CGFloat(headers) * Self.groupHeaderHeight
    }

    /// The whole list, scrolled or not.
    var contentHeight: CGFloat {
        sessionCount == 0 ? 0 : rowOffset(sessionCount - 1) + Self.rowHeight
    }

    var scrolls: Bool { contentHeight > Self.maxBodyHeight }

    var panelRect: CGRect {
        let body = sessionCount == 0 ? Self.emptyStateHeight : min(contentHeight, Self.maxBodyHeight)
        let height = Self.headerHeight + body + Self.panelBottomPadding
        return CGRect(
            x: columnRect.minX - Self.panelGap - Self.panelWidth,
            y: ((Self.canvas.height - height) / 2).rounded(),
            width: Self.panelWidth,
            height: height
        )
    }

    func rowRect(_ index: Int) -> CGRect {
        let top = panelRect.maxY - Self.headerHeight - rowOffset(index)
        return CGRect(x: panelRect.minX, y: top - Self.rowHeight, width: panelRect.width, height: Self.rowHeight)
    }

    /// Row under the point; nil when the list scrolls (rows no longer sit at fixed places).
    func rowIndex(at point: CGPoint) -> Int? {
        guard !scrolls else { return nil }
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

extension SessionStore {
    /// The widget's geometry for the sessions shown right now.
    var metrics: WidgetMetrics {
        WidgetMetrics(groupSizes: groups.map(\.sessions.count))
    }
}
