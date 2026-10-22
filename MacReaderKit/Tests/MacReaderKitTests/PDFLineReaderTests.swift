import PDFKit
import Testing
@testable import MacReaderKit

struct PDFLineReaderTests {
    @Test func readsEachLineWithItsFontSizeAndPage() throws {
        let data = PDFFixtures.makeStyledPDF(pages: [
            [.init(text: "Big Title", size: 30), .init(text: "small body line", size: 12)],
            [.init(text: "second page line", size: 12)],
        ])
        let lines = PDFLineReader.lines(in: try #require(PDFDocument(data: data)))

        #expect(lines.map(\.text) == ["Big Title", "small body line", "second page line"])
        #expect(lines.map(\.pageIndex) == [0, 0, 1])
        #expect(lines.map { Int($0.fontSize.rounded()) } == [30, 12, 12])
    }

    @Test func readsEachLinesBoundsOnThePage() throws {
        let lines = PDFLineReader.lines(in: try #require(PDFDocument(data: PDFFixtures.makeVisualPDF())))
        let boxed = try #require(lines.first { $0.text == "Boxed note" })
        #expect(PDFFixtures.visualBox.contains(boxed.bounds))
        let before = try #require(lines.first { $0.text == "Before the box" })
        #expect(before.bounds.minY > PDFFixtures.visualBox.maxY)
    }

    @Test func boundsStartAtTheVisibleTextNotAtLeadingSpaces() throws {
        // Courier at 12pt is 7.2pt per character, so three spaces push "spaced" about 21.6pt right of "flat".
        let data = PDFFixtures.makeIndentedPDF([("flat", 72), ("   spaced", 72), ("moved", 100)])
        let lines = PDFLineReader.lines(in: try #require(PDFDocument(data: data)))
        let flat = try #require(lines.first { $0.text == "flat" })
        let spaced = try #require(lines.first { $0.text == "spaced" })
        let moved = try #require(lines.first { $0.text == "moved" })

        #expect(abs(spaced.bounds.minX - flat.bounds.minX - 21.6) < 2)
        #expect(abs(moved.bounds.minX - flat.bounds.minX - 28) < 2)
    }
}
