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
}
