import Foundation
import Testing
@testable import MacReaderKit

struct PDFTextExtractorTests {
    @Test func extractsTextFromAllPages() throws {
        let pdf = PDFFixtures.makePDF(pages: ["Alpha page one.", "Beta page two."])
        let result = try PDFTextExtractor.extract(from: pdf)
        #expect(result.text.contains("Alpha page one."))
        #expect(result.text.contains("Beta page two."))
        #expect(result.pageCount == 2)
    }

    @Test func readsTitleAttribute() throws {
        let pdf = PDFFixtures.makePDF(pages: ["Hello"], title: "My Title")
        #expect(try PDFTextExtractor.extract(from: pdf).title == "My Title")
    }

    @Test func throwsUnreadableForGarbage() {
        #expect(throws: PDFTextExtractor.Failure.unreadable) {
            try PDFTextExtractor.extract(from: Data("not a pdf".utf8))
        }
    }

    @Test func throwsNoTextForBlankPDF() {
        let pdf = PDFFixtures.makePDF(pages: ["", ""])
        #expect(throws: PDFTextExtractor.Failure.noText) {
            try PDFTextExtractor.extract(from: pdf)
        }
    }
}
