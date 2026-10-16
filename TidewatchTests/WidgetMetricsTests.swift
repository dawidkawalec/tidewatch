import CoreGraphics
import Testing
@testable import Tidewatch

struct WidgetMetricsTests {
    @Test func columnHugsTheRightEdgeAndIsCentred() {
        let m = WidgetMetrics(sessionCount: 5)
        #expect(m.columnRect.maxX == m.canvas.width - WidgetMetrics.edgeGap)
        #expect(m.columnRect.width == WidgetMetrics.columnWidth)
        #expect(abs(m.columnRect.midY - m.canvas.height / 2) <= 1)
        #expect(m.columnRect.height == 5 * WidgetMetrics.lampPitch + 2 * WidgetMetrics.columnPadding)
    }

    /// The owner, 2026-10-16: no scrolling, everything visible; desktop only, so it may be long.
    /// The canvas is as tall as the screen, so 18 sessions show every lamp and every row.
    @Test func aTallScreenShowsEveryLampAndRow() {
        let m = WidgetMetrics(groupSizes: Array(repeating: 1, count: 18), canvasHeight: 1080)
        #expect(m.visibleLamps == 18)
        #expect(!m.hasOverflow)
        #expect(!m.scrolls)
        #expect(m.panelRect.height == WidgetMetrics.headerHeight + 18 * WidgetMetrics.rowHeight + WidgetMetrics.panelBottomPadding)
        #expect(m.panelRect.minY >= WidgetMetrics.screenMargin)
        #expect(m.panelRect.maxY <= 1080 - WidgetMetrics.screenMargin)
        #expect(m.columnRect.minY >= WidgetMetrics.screenMargin)
    }

    /// Only more sessions than the screen holds fall back to the chevron and scrolling.
    @Test func onlyMoreThanTheScreenHoldsOverflows() {
        #expect(WidgetMetrics(sessionCount: 0).visibleLamps == 1)
        let many = WidgetMetrics(sessionCount: 40, canvasHeight: 600)
        #expect(many.hasOverflow)
        #expect(many.visibleLamps == many.maxLamps)
        #expect(many.visibleLamps < 40)
        #expect(many.columnRect.height <= 600 - 2 * WidgetMetrics.screenMargin)
        #expect(many.columnRect.height == CGFloat(many.maxLamps) * WidgetMetrics.lampPitch + 2 * WidgetMetrics.columnPadding + WidgetMetrics.chevronHeight)
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

    @Test func aListTallerThanTheScreenScrollsAsAFallback() {
        let m = WidgetMetrics(sessionCount: 12, canvasHeight: 600)
        #expect(m.scrolls)
        #expect(m.maxScroll == 12 * WidgetMetrics.rowHeight - m.maxBodyHeight)
        #expect(m.panelRect.maxY <= 600 - WidgetMetrics.screenMargin)
        #expect(m.panelRect.height == WidgetMetrics.headerHeight + m.maxBodyHeight + WidgetMetrics.panelBottomPadding)
        #expect(m.clampedScroll(-20) == 0)
        #expect(m.clampedScroll(10_000) == m.maxScroll)
        #expect(WidgetMetrics(sessionCount: 9, canvasHeight: 1080).maxScroll == 0)
    }

    /// Rows hit-test where they are drawn: scrolled up by `offset`, and only inside the list.
    @Test func scrolledRowsHitTestWhereTheyAreDrawn() {
        let m = WidgetMetrics(sessionCount: 12, canvasHeight: 600)
        let offset = m.maxScroll
        let last = m.rowRect(11, offset: offset)
        #expect(m.rowIndex(at: CGPoint(x: last.midX, y: last.midY), offset: offset) == 11)
        #expect(last.minY >= m.panelRect.minY)
        // The first row scrolled out above the list is not hoverable over the header.
        let first = m.rowRect(0, offset: offset)
        #expect(m.rowIndex(at: CGPoint(x: first.midX, y: first.midY), offset: offset) == nil)
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

    /// The owner asked for a panel 50 pt wider (330); it must still fit the canvas.
    @Test func theWiderPanelFitsTheCanvas() {
        #expect(WidgetMetrics.panelWidth == 330)
        #expect(WidgetMetrics(sessionCount: 3).panelRect.minX >= 0)
    }

    /// The canvas fills the visible frame's height at its right edge (transparent pixels let
    /// clicks through), so the widget can grow to the screen's height.
    @Test func canvasFillsTheRightEdgeOfTheVisibleFrame() {
        let frame = CGRect(x: 0, y: 25, width: 1728, height: 1055)
        #expect(WidgetMetrics.canvasFrame(in: frame) == CGRect(x: 1728 - WidgetMetrics.canvasWidth, y: 25, width: WidgetMetrics.canvasWidth, height: 1055))
    }

    /// Previews and the page recordings keep the 402 x 600 canvas.
    @Test func previewsKeepTheFixedCanvas() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let canvas = WidgetMetrics.canvasFrame(in: frame, height: WidgetMetrics.defaultCanvasHeight)
        #expect(canvas.size == CGSize(width: 402, height: 600))
        #expect(canvas.origin == CGPoint(x: 1728 - 402, y: 240))
    }
}
