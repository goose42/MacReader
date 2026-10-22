import Foundation
import Testing
@testable import MacReaderKit

struct PDFTextExtractorTests {
    private typealias Run = PDFFixtures.Run

    private let body = "Body text that runs long enough to be the dominant size in this document."

    @Test func extractsTextFromAllPages() throws {
        let pdf = PDFFixtures.makePDF(pages: ["Alpha page one.", "Beta page two."])
        let result = try PDFTextExtractor.extract(from: pdf)
        #expect(result.document.plainText.contains("Alpha page one."))
        #expect(result.document.plainText.contains("Beta page two."))
        #expect(result.pageCount == 2)
    }

    @Test func prefersTheTitleAttributeOverTheFallback() throws {
        let pdf = PDFFixtures.makePDF(pages: ["Hello"], title: "My Title")
        #expect(try PDFTextExtractor.extract(from: pdf, fallbackTitle: "file").document.title == "My Title")
    }

    @Test func usesTheFallbackTitleWhenThereIsNone() throws {
        let pdf = PDFFixtures.makePDF(pages: ["Hello"])
        #expect(try PDFTextExtractor.extract(from: pdf, fallbackTitle: "file").document.title == "file")
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

    @Test func buildsAnAppOwnedTableOfContentsFromHeadingSizes() throws {
        let pdf = PDFFixtures.makeStyledPDF(pages: [
            [Run(text: "First Section", size: 24), Run(text: body, size: 12)],
            [Run(text: "Second Section", size: 24), Run(text: body, size: 12)],
        ])
        let document = try PDFTextExtractor.extract(from: pdf).document
        #expect(document.tableOfContents.map(\.title) == ["First Section", "Second Section"])
    }

    @Test func dropsThePrintedContentsPage() throws {
        let pdf = PDFFixtures.makeStyledPDF(pages: [
            [Run(text: "CONTENTS", size: 9), Run(text: "Alpha Section", size: 9), Run(text: "Beta Section", size: 9)],
            [Run(text: "Alpha Section", size: 24), Run(text: body, size: 12)],
            [Run(text: "Beta Section", size: 24), Run(text: body, size: 12)],
        ])
        let document = try PDFTextExtractor.extract(from: pdf).document
        #expect(!document.plainText.contains("CONTENTS"))
        #expect(document.tableOfContents.map(\.title) == ["Alpha Section", "Beta Section"])
    }

    @Test func prefersThePDFOutlineWhenItHasOne() throws {
        let pdf = PDFFixtures.makeStyledPDF(
            pages: [[Run(text: "Chapter A", size: 12), Run(text: body, size: 12)]],
            outline: [(label: "Chapter A", page: 0)])
        let document = try PDFTextExtractor.extract(from: pdf).document
        #expect(document.tableOfContents.map(\.title) == ["Chapter A"])
    }

    @Test func repairsBrokenLigaturesUsingTheSystemSpellChecker() throws {
        let pdf = PDFFixtures.makeStyledPDF(pages: [[
            Run(text: "Dnally the Dle was Drst, and speciDc.", size: 12),
        ]])
        let text = try PDFTextExtractor.extract(from: pdf).document.plainText
        #expect(text == "finally the file was first, and specific.")
    }

    @Test func turnsBoxedTextIntoACalloutAndPicturesIntoRenderedImages() throws {
        let result = try PDFTextExtractor.extract(from: PDFFixtures.makeVisualPDF())

        #expect(result.document.blocks.map(\.kind) == [
            .paragraph, .callout, .paragraph, .image(name: "p1-1.png", aspectRatio: 2),
        ])
        #expect(result.document.blocks[1].text == "Boxed note")
        let png = try #require(result.images["p1-1.png"])
        #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }
}
