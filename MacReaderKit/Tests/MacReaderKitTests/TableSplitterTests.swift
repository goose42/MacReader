import CoreGraphics
import Testing
@testable import MacReaderKit

struct TableSplitterTests {
    private let grid = TableGrid(
        pageIndex: 0, columns: [300...329, 331...379, 381...430], rules: [300, 250, 200], top: 320, bottom: 180)

    /// Characters 7pt wide laid out from the line's left edge.
    private func evenly(_ line: TextLine) -> [CGRect]? {
        line.text.enumerated().map {
            CGRect(x: line.bounds.minX + CGFloat($0.offset) * 7, y: line.bounds.minY, width: 7, height: line.bounds.height)
        }
    }

    private func line(_ text: String, x: CGFloat = 300, y: CGFloat = 270, page: Int = 0) -> TextLine {
        var line = TextLine(text: text, fontSize: 12, pageIndex: page, bounds: CGRect(x: x, y: y, width: CGFloat(text.count) * 7, height: 14))
        line.sourceLocation = 100
        return line
    }

    @Test func cutsALineAtTheColumnBoundariesItCrosses() {
        let result = TableSplitter.split([line("a      b      c")], tables: [grid], characterBounds: evenly)

        #expect(result.map(\.text) == ["a", "b", "c"])
        #expect(result.map(\.bounds.minX) == [300, 349, 398])
        #expect(result.map(\.bounds.width) == [7, 7, 7])
    }

    @Test func keepsEachFragmentsPlaceInThePageText() {
        let result = TableSplitter.split([line("a      b")], tables: [grid], characterBounds: evenly)
        #expect(result.map(\.sourceLocation) == [100, 107])
    }

    @Test func leavesALineInsideOneColumnAlone() {
        let inside = line("narrow", x: 332)
        #expect(TableSplitter.split([inside], tables: [grid], characterBounds: evenly) == [inside])
    }

    @Test func leavesLinesOutsideEveryTableAlone() {
        let outside = [line("a      b      c", y: 600), line("a      b      c", page: 1)]
        #expect(TableSplitter.split(outside, tables: [grid], characterBounds: evenly) == outside)
    }

    @Test func dropsTheBlankSpaceBetweenFragments() {
        let result = TableSplitter.split([line("a      b")], tables: [grid]) { line in
            // Spaces have no glyph, so PDFKit reports an empty box for them.
            line.text.enumerated().map {
                $0.element == " " ? .zero : CGRect(x: line.bounds.minX + CGFloat($0.offset) * 7, y: line.bounds.minY, width: 7, height: line.bounds.height)
            }
        }
        #expect(result.map(\.text) == ["a", "b"])
    }

    @Test func keepsALineWhoseCharacterBoundsAreUnavailable() {
        let crossing = line("a      b      c")
        #expect(TableSplitter.split([crossing], tables: [grid]) { _ in nil } == [crossing])
        #expect(TableSplitter.split([crossing], tables: [grid]) { _ in [] } == [crossing])
    }
}
