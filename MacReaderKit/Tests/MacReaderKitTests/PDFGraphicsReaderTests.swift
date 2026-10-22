import PDFKit
import Testing
@testable import MacReaderKit

struct PDFGraphicsReaderTests {
    private func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    @Test func findsFilledRectanglesAndDrawnImagesWithTheirFrames() throws {
        let pdf = try #require(PDFDocument(data: PDFFixtures.makeVisualPDF()))
        let graphics = try #require(PDFGraphicsReader.graphics(in: pdf).first)

        #expect(graphics.pageIndex == 0)
        #expect(graphics.size == CGSize(width: 612, height: 792))
        #expect(graphics.rects.contains { near($0, PDFFixtures.visualBox) })
        #expect(graphics.images.count == 1)
        #expect(near(graphics.images[0], PDFFixtures.visualImage))
    }

    @Test func reportsNothingForAPageOfPlainText() throws {
        let pdf = try #require(PDFDocument(data: PDFFixtures.makePDF(pages: ["Just words."])))
        let graphics = try #require(PDFGraphicsReader.graphics(in: pdf).first)
        #expect(graphics.rects.isEmpty)
        #expect(graphics.images.isEmpty)
    }
}
