import CoreGraphics
import Testing
@testable import MacReaderKit

struct TableDetectorTests {
    private let size = CGSize(width: 612, height: 792)
    /// The module table of a real PDF: one rule segment per column cell, 1pt apart.
    private let columns: [ClosedRange<CGFloat>] = [300...329, 330...426, 426...541, 541...605]

    private func rules(at ys: [CGFloat], columns: [ClosedRange<CGFloat>]? = nil) -> [CGRect] {
        ys.flatMap { y in (columns ?? self.columns).map { CGRect(x: $0.lowerBound, y: y - 0.5, width: $0.upperBound - $0.lowerBound, height: 1) } }
    }

    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 80, height: CGFloat = 16, size: Double = 12) -> TextLine {
        TextLine(text: text, fontSize: size, pageIndex: 0, bounds: CGRect(x: x, y: y, width: width, height: height))
    }

    private func graphics(_ rects: [CGRect]) -> PageGraphics {
        PageGraphics(pageIndex: 0, size: size, rects: rects)
    }

    private var tableText: [TextLine] {
        [
            line("Contents heading", x: 300, y: 350, width: 280, height: 29, size: 24),
            line("# MODULE", x: 312, y: 313, height: 12, size: 9.6), line("HERE", x: 437, y: 300, height: 12, size: 9.6),
            line("1 Python", x: 312, y: 265), line("fluency", x: 341, y: 247),
            line("2 Async", x: 312, y: 178), line("3 DB", x: 312, y: 100),
            line("closing paragraph", x: 300, y: 30, width: 240, height: 19, size: 13.6),
        ]
    }

    @Test func findsColumnsRowRulesAndTheTextExtentOfARuledTable() throws {
        let grid = try #require(TableDetector.tables(in: graphics(rules(at: [289, 203, 134])), lines: tableText).first)

        #expect(grid.columns == columns)
        #expect(grid.rules == [289, 203, 134])
        #expect(grid.hasHeader)
        #expect(grid.top == 325)       // the header text, not the larger heading above it
        #expect(grid.bottom == 100)    // the row under the last rule, not the paragraph after the gap
    }

    @Test func collapsesRulesThatAreDrawnTwice() throws {
        let doubled = rules(at: [289, 203, 134]) + rules(at: [289, 203, 134])
        let grid = try #require(TableDetector.tables(in: graphics(doubled), lines: tableText).first)
        #expect(grid.rules == [289, 203, 134])
    }

    @Test func aSingleFullWidthRuleIsNotATable() {
        let rule = [CGRect(x: 72, y: 400, width: 468, height: 1), CGRect(x: 72, y: 300, width: 468, height: 1)]
        #expect(TableDetector.tables(in: graphics(rule), lines: []).isEmpty)
    }

    @Test func underlinesWithDifferentShapesAreNotATable() {
        // Link underlines break at spaces, and no two lines break in the same places.
        let underlines = [
            CGRect(x: 72, y: 700, width: 40, height: 1), CGRect(x: 116, y: 700, width: 60, height: 1),
            CGRect(x: 72, y: 680, width: 90, height: 1), CGRect(x: 166, y: 680, width: 30, height: 1),
        ]
        #expect(TableDetector.tables(in: graphics(underlines), lines: []).isEmpty)
    }

    @Test func aTableNeedsAtLeastTwoRuleLevels() {
        #expect(TableDetector.tables(in: graphics(rules(at: [289])), lines: tableText).isEmpty)
    }

    @Test func hasNoHeaderWhenNoTextSitsAboveTheFirstRule() throws {
        let body = tableText.filter { $0.bounds.maxY < 289 }
        let grid = try #require(TableDetector.tables(in: graphics(rules(at: [289, 203, 134])), lines: body).first)
        #expect(!grid.hasHeader)
        #expect(grid.top == 289)
    }

    @Test func ignoresRulesOutsideThePageAndClipsOverhangingColumns() throws {
        let wide: [ClosedRange<CGFloat>] = [300...350, 350...481, 481...677]
        let offPage = rules(at: [1699, 1500], columns: wide)
        let onPage = rules(at: [748, 679], columns: wide)
        let grid = try #require(TableDetector.tables(in: graphics(offPage + onPage), lines: []).first)
        #expect(grid.rules == [748, 679])
        #expect(grid.columns.last == 481...612)
    }

    // MARK: - Tables that run across pages

    private func page(_ index: Int, rules ys: [CGFloat], lines: [TextLine]) -> (PageGraphics, [TextLine]) {
        (PageGraphics(pageIndex: index, size: size, rects: rules(at: ys)), lines.map {
            TextLine(text: $0.text, fontSize: $0.fontSize, pageIndex: index, bounds: $0.bounds)
        })
    }

    @Test func marksATableThatStartsAtTheTopOfThePageAfterOneEndingAtTheBottomAsItsContinuation() {
        let first = page(0, rules: [300, 200, 100], lines: [line("last row", x: 312, y: 60)])
        let second = page(1, rules: [700, 600], lines: [line("more", x: 312, y: 640)])
        let grids = TableDetector.tables(inPages: [first.0, second.0], lines: first.1 + second.1)

        #expect(grids.map(\.pageIndex) == [0, 1])
        #expect(grids.map(\.continuesPrevious) == [false, true])
    }

    @Test func doesNotJoinTablesWhenThePreviousOneEndsMidPage() {
        let first = page(0, rules: [700, 600], lines: [])
        let second = page(1, rules: [700, 600], lines: [])
        #expect(TableDetector.tables(inPages: [first.0, second.0], lines: []).map(\.continuesPrevious) == [false, false])
    }

    @Test func doesNotJoinTablesWithDifferentColumns() {
        let first = page(0, rules: [300, 200, 100], lines: [])
        let other: [ClosedRange<CGFloat>] = [300...400, 401...605]
        let second = PageGraphics(pageIndex: 1, size: size, rects: rules(at: [700, 600], columns: other))
        #expect(TableDetector.tables(inPages: [first.0, second], lines: []).map(\.continuesPrevious) == [false, false])
    }

    @Test func doesNotJoinTablesOnPagesThatAreNotConsecutive() {
        let first = page(0, rules: [300, 200, 100], lines: [])
        let third = page(2, rules: [700, 600], lines: [])
        #expect(TableDetector.tables(inPages: [first.0, third.0], lines: []).map(\.continuesPrevious) == [false, false])
    }
}
