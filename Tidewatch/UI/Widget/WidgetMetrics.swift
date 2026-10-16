import CoreGraphics

/// Geometry of the widget canvas in points, origin bottom left (AppKit). The SwiftUI layout and
/// the hover hit tests both read it, so they always agree.
///
/// Sessions come in windows (`groupSizes`, in widget order). A window with several tabs is parted
/// from its neighbours by a gap in the column and gets a header in the list; windows with one tab
/// each look like a plain list.
///
/// The canvas is as tall as the screen's visible frame (owner, 2026-10-16: no scrolling, every
/// session visible), so the column and the list grow with the sessions. Only more sessions than
/// the screen holds fall back to the chevron and scrolling. Previews keep 402 x 600.
struct WidgetMetrics: Equatable, Sendable {
    static let canvasWidth: CGFloat = 402
    /// The design previews and the page recordings.
    static let defaultCanvasHeight: CGFloat = 600
    /// Kept clear above and below the column and the panel.
    static let screenMargin: CGFloat = 12
    static let edgeGap: CGFloat = 8
    static let columnWidth: CGFloat = 36
    static let columnPadding: CGFloat = 9
    static let lampPitch: CGFloat = 26
    static let lampSize: CGFloat = 12
    static let groupGap: CGFloat = 10
    static let chevronHeight: CGFloat = 16
    static let panelGap: CGFloat = 16
    static let panelWidth: CGFloat = 330
    static let headerHeight: CGFloat = 52
    static let groupHeaderHeight: CGFloat = 26
    static let rowHeight: CGFloat = 50
    static let panelBottomPadding: CGFloat = 8
    static let emptyStateHeight: CGFloat = 96
    static let hoverSlop: CGFloat = 8
    static let expandDelay: Duration = .milliseconds(280)
    static let collapseDelay: Duration = .milliseconds(450)
    static let pointerPoll: Duration = .milliseconds(150)

    let groupSizes: [Int]
    let canvas: CGSize
    /// Per session in widget order: whether its window has several tabs, and whether it is the
    /// first of its window.
    private let grouped: [Bool]
    private let opensGroup: [Bool]

    init(groupSizes: [Int], canvasHeight: CGFloat = Self.defaultCanvasHeight) {
        canvas = CGSize(width: Self.canvasWidth, height: canvasHeight)
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
    init(sessionCount: Int, canvasHeight: CGFloat = Self.defaultCanvasHeight) {
        self.init(groupSizes: Array(repeating: 1, count: max(sessionCount, 0)), canvasHeight: canvasHeight)
    }

    var sessionCount: Int { grouped.count }

    /// Height the column and the panel may take.
    private var usableHeight: CGFloat { canvas.height - 2 * Self.screenMargin }

    /// How many lamps the column shows: all of them while they fit the screen.
    var maxLamps: Int {
        let room = usableHeight - 2 * Self.columnPadding
        if sessionCount == 0 || lampOffset(sessionCount - 1) + Self.lampPitch <= room { return max(sessionCount, 1) }
        let withChevron = room - Self.chevronHeight
        return (1..<sessionCount).last { lampOffset($0 - 1) + Self.lampPitch <= withChevron } ?? 1
    }

    /// No sessions still shows one dim lamp.
    var visibleLamps: Int { min(max(sessionCount, 1), maxLamps) }
    var hasOverflow: Bool { sessionCount > maxLamps }

    /// The list scrolls only past this: the screen's height minus the panel's header.
    var maxBodyHeight: CGFloat { usableHeight - Self.headerHeight - Self.panelBottomPadding }

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
            x: canvas.width - Self.edgeGap - Self.columnWidth,
            y: ((canvas.height - height) / 2).rounded(),
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
        return (0..<min(sessionCount, maxLamps)).first { abs(lampCenter($0).y - point.y) < Self.lampPitch / 2 }
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

    var scrolls: Bool { contentHeight > maxBodyHeight }

    /// How far the list scrolls (the widget scrolls it itself: the panel never becomes key, so a
    /// SwiftUI ScrollView in it gets no scroll events).
    var maxScroll: CGFloat { max(0, contentHeight - maxBodyHeight) }

    func clampedScroll(_ offset: CGFloat) -> CGFloat {
        min(max(offset, 0), maxScroll)
    }

    /// The list's visible area.
    var bodyRect: CGRect {
        let height = min(contentHeight, maxBodyHeight)
        return CGRect(x: panelRect.minX, y: panelRect.maxY - Self.headerHeight - height, width: panelRect.width, height: height)
    }

    var panelRect: CGRect {
        let body = sessionCount == 0 ? Self.emptyStateHeight : min(contentHeight, maxBodyHeight)
        let height = Self.headerHeight + body + Self.panelBottomPadding
        return CGRect(
            x: columnRect.minX - Self.panelGap - Self.panelWidth,
            y: ((canvas.height - height) / 2).rounded(),
            width: Self.panelWidth,
            height: height
        )
    }

    /// Where row `index` is drawn with the list scrolled up by `offset`.
    func rowRect(_ index: Int, offset: CGFloat = 0) -> CGRect {
        let top = panelRect.maxY - Self.headerHeight - rowOffset(index) + offset
        return CGRect(x: panelRect.minX, y: top - Self.rowHeight, width: panelRect.width, height: Self.rowHeight)
    }

    /// Row under the point, only inside the visible list.
    func rowIndex(at point: CGPoint, offset: CGFloat = 0) -> Int? {
        guard bodyRect.contains(point) else { return nil }
        return (0..<sessionCount).first { rowRect($0, offset: offset).contains(point) }
    }

    /// While expanded, the bounding box of column + panel, so crossing the gap keeps it open.
    func hoverRect(expanded: Bool) -> CGRect {
        let base = expanded ? columnRect.union(panelRect) : columnRect
        return base.insetBy(dx: -Self.hoverSlop, dy: -Self.hoverSlop)
    }

    /// The canvas window: glued to the right edge of the visible frame, as tall as it (or `height`,
    /// centred vertically).
    static func canvasFrame(in visibleFrame: CGRect, height: CGFloat? = nil) -> CGRect {
        let height = height ?? visibleFrame.height
        return CGRect(x: visibleFrame.maxX - canvasWidth, y: (visibleFrame.midY - height / 2).rounded(), width: canvasWidth, height: height)
    }
}

extension SessionStore {
    /// The widget's geometry for the sessions shown right now, on a canvas this tall.
    func metrics(canvasHeight: CGFloat) -> WidgetMetrics {
        WidgetMetrics(groupSizes: groups.map(\.sessions.count), canvasHeight: canvasHeight)
    }
}
