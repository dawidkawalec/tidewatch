import CoreGraphics
import Testing
@testable import Tidewatch

struct WidgetMetricsTests {
    @Test func columnHugsTheRightEdgeAndIsCentred() {
        let m = WidgetMetrics(sessionCount: 5)
        #expect(m.columnRect.maxX == WidgetMetrics.canvas.width - WidgetMetrics.edgeGap)
        #expect(m.columnRect.width == WidgetMetrics.columnWidth)
        #expect(abs(m.columnRect.midY - WidgetMetrics.canvas.height / 2) <= 1)
        #expect(m.columnRect.height == 5 * WidgetMetrics.lampPitch + 2 * WidgetMetrics.columnPadding)
    }

    @Test func emptyShowsOneLampAndOverflowAddsTheChevron() {
        #expect(WidgetMetrics(sessionCount: 0).visibleLamps == 1)
        let many = WidgetMetrics(sessionCount: WidgetMetrics.maxLamps + 3)
        #expect(many.visibleLamps == WidgetMetrics.maxLamps)
        #expect(many.hasOverflow)
        #expect(many.columnRect.height == CGFloat(WidgetMetrics.maxLamps) * WidgetMetrics.lampPitch + 2 * WidgetMetrics.columnPadding + WidgetMetrics.chevronHeight)
    }

    @Test func lampHitTestingMatchesLampCentres() {
        let m = WidgetMetrics(sessionCount: 4)
        for index in 0..<4 {
            #expect(m.lampIndex(at: m.lampCenter(index)) == index)
        }
        #expect(m.lampIndex(at: CGPoint(x: 0, y: 0)) == nil)
        #expect(WidgetMetrics(sessionCount: 0).lampIndex(at: WidgetMetrics(sessionCount: 0).lampCenter(0)) == nil)
    }

    @Test func panelSitsLeftOfTheColumnAndRowsHitTest() {
        let m = WidgetMetrics(sessionCount: 3)
        #expect(m.panelRect.maxX == m.columnRect.minX - WidgetMetrics.panelGap)
        #expect(m.panelRect.width == WidgetMetrics.panelWidth)
        #expect(m.panelRect.height == WidgetMetrics.headerHeight + 3 * WidgetMetrics.rowHeight + WidgetMetrics.panelBottomPadding)
        #expect(m.panelRect.minX >= 0)
        for index in 0..<3 {
            let rect = m.rowRect(index)
            #expect(m.rowIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == index)
        }
        #expect(m.rowIndex(at: CGPoint(x: m.panelRect.midX, y: m.panelRect.maxY - 5)) == nil)
    }

    @Test func scrollingListHasNoRowHitTesting() {
        let m = WidgetMetrics(sessionCount: 9)
        #expect(m.scrolls)
        let rect = m.rowRect(0)
        #expect(m.rowIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == nil)
        #expect(m.panelRect.maxY <= WidgetMetrics.canvas.height)
        #expect(m.panelRect.height == WidgetMetrics.headerHeight + WidgetMetrics.maxBodyHeight + WidgetMetrics.panelBottomPadding)
    }

    // MARK: Windows

    /// The tabs of one window sit together; a gap parts them from the next window. Windows with
    /// one tab each keep the plain pitch.
    @Test func lampsOfAWindowWithSeveralTabsArePartedFromTheOthers() {
        let m = WidgetMetrics(groupSizes: [2, 1, 1])
        #expect(m.sessionCount == 4)
        #expect((0..<4).map(m.gapBefore) == [false, false, true, false])
        #expect(m.columnRect.height == 4 * WidgetMetrics.lampPitch + WidgetMetrics.groupGap + 2 * WidgetMetrics.columnPadding)
        #expect(m.lampCenter(1).y - m.lampCenter(2).y == WidgetMetrics.lampPitch + WidgetMetrics.groupGap)
        #expect(m.lampCenter(2).y - m.lampCenter(3).y == WidgetMetrics.lampPitch)
        for index in 0..<4 {
            #expect(m.lampIndex(at: m.lampCenter(index)) == index)
        }
        let gap = CGPoint(x: m.columnRect.midX, y: m.lampCenter(1).y - WidgetMetrics.lampPitch / 2 - WidgetMetrics.groupGap / 2)
        #expect(m.lampIndex(at: gap) == nil)
    }

    @Test func aWindowWithSeveralTabsGetsAHeaderInTheList() {
        let m = WidgetMetrics(groupSizes: [1, 2])
        #expect((0..<3).map(m.headerBefore) == [false, true, false])
        #expect(m.panelRect.height == WidgetMetrics.headerHeight + 3 * WidgetMetrics.rowHeight + WidgetMetrics.groupHeaderHeight + WidgetMetrics.panelBottomPadding)
        #expect(m.rowRect(0).minY - m.rowRect(1).maxY == WidgetMetrics.groupHeaderHeight)
        #expect(m.rowRect(1).minY == m.rowRect(2).maxY)
        for index in 0..<3 {
            let rect = m.rowRect(index)
            #expect(m.rowIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == index)
        }
        let header = CGPoint(x: m.panelRect.midX, y: m.rowRect(1).maxY + WidgetMetrics.groupHeaderHeight / 2)
        #expect(m.rowIndex(at: header) == nil)
    }

    @Test func oneTabPerWindowLooksLikeAPlainList() {
        #expect(WidgetMetrics(groupSizes: [1, 1, 1]) == WidgetMetrics(sessionCount: 3))
        #expect(WidgetMetrics(groupSizes: [1, 1, 1]).columnRect == WidgetMetrics(groupSizes: [3]).columnRect)
    }

    @Test func hoverAreaGrowsWhenExpanded() {
        let m = WidgetMetrics(sessionCount: 2)
        #expect(m.hoverRect(expanded: false).contains(m.lampCenter(0)))
        #expect(!m.hoverRect(expanded: false).contains(CGPoint(x: m.panelRect.midX, y: m.panelRect.midY)))
        #expect(m.hoverRect(expanded: true).contains(CGPoint(x: m.panelRect.midX, y: m.panelRect.midY)))
        // The gap between panel and column keeps the panel open.
        #expect(m.hoverRect(expanded: true).contains(CGPoint(x: m.panelRect.maxX + WidgetMetrics.panelGap / 2, y: m.columnRect.midY)))
    }

    @Test func canvasIsGluedToTheRightOfTheVisibleFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let origin = WidgetMetrics.canvasOrigin(in: frame)
        #expect(origin.x == 1728 - WidgetMetrics.canvas.width)
        #expect(origin.y == (540 - WidgetMetrics.canvas.height / 2).rounded())
    }
}
