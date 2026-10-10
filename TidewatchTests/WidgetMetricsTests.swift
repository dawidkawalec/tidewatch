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
        let many = WidgetMetrics(sessionCount: 9)
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
        let m = WidgetMetrics(sessionCount: WidgetMetrics.maxVisibleRows + 1)
        let rect = m.rowRect(0)
        #expect(m.rowIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == nil)
        #expect(m.panelRect.maxY <= WidgetMetrics.canvas.height)
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
