import Testing
@testable import MacReaderKit

struct StructureBuilderTests {
    private func line(_ text: String, _ size: Double, page: Int = 0) -> TextLine {
        TextLine(text: text, fontSize: size, pageIndex: page)
    }

    private typealias Block = ReaderDocument.Block

    @Test func emptyInputYieldsAnEmptyDocumentWithTheFallbackTitle() {
        let doc = StructureBuilder.build(lines: [], fallbackTitle: "Fallback")
        #expect(doc == ReaderDocument(title: "Fallback", blocks: []))
    }

    @Test func buildsHeadingsByFontSizeMergingWrappedLines() {
        let doc = StructureBuilder.build(lines: [
            line("Practical", 40), line("Guide", 40),
            line("Section", 24), line("One", 24),
            line("Body line one", 13.6), line("continues here.", 13.6),
            line("A sub topic", 17.6),
            line("More body text follows after the sub topic heading.", 13.6),
            line("Section Two", 24, page: 1),
            line("Final body text for the last section of the doc.", 13.6, page: 1),
        ], fallbackTitle: "Fallback")

        #expect(doc.title == "Practical Guide")
        #expect(doc.blocks == [
            Block(id: 0, kind: .heading(level: 1), text: "Section One"),
            Block(id: 1, kind: .paragraph, text: "Body line one continues here."),
            Block(id: 2, kind: .heading(level: 2), text: "A sub topic"),
            Block(id: 3, kind: .paragraph, text: "More body text follows after the sub topic heading."),
            Block(id: 4, kind: .heading(level: 1), text: "Section Two"),
            Block(id: 5, kind: .paragraph, text: "Final body text for the last section of the doc."),
        ])
    }

    @Test func normalisesBodyRuns() {
        let doc = StructureBuilder.build(lines: [
            line("an exam-", 12), line("ple   of it that goes on for a while.", 12),
        ], fallbackTitle: "T")
        #expect(doc.blocks.map(\.text) == ["an example of it that goes on for a while."])
    }

    @Test func doesNotTakeATitleWhenTheLargestSizeRepeats() {
        let doc = StructureBuilder.build(lines: [
            line("First", 24), line("body body body body body body.", 12),
            line("Second", 24, page: 1), line("body body body body body body.", 12, page: 1),
        ], fallbackTitle: "Fallback")
        #expect(doc.title == "Fallback")
        #expect(doc.tableOfContents.map(\.title) == ["First", "Second"])
        #expect(doc.tableOfContents.allSatisfy { $0.level == 1 })
    }

    @Test func capsHeadingLevelsAtThree() {
        let doc = StructureBuilder.build(lines: [
            line("H-a", 30), line("body body body body body body body body body body.", 12),
            line("H-b", 28), line("body body body body body body body body body body.", 12),
            line("H-c", 26), line("body body body body body body body body body body.", 12),
            line("H-d", 24), line("body body body body body body body body body body.", 12),
            line("H-a", 30, page: 1),
        ], fallbackTitle: "T")
        #expect(doc.tableOfContents.map(\.level) == [1, 2, 3, 3, 1])
    }

    @Test func usesTheOutlineInsteadOfFontSizesWhenOneExists() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 12), line("alpha body text that is long enough to be body text.", 12),
            line("Beta", 24, page: 1), line("beta body text that is long enough to be body text.", 12, page: 1),
        ], fallbackTitle: "T", outline: [
            OutlineEntry(label: "Alpha", level: 1, pageIndex: 0),
            OutlineEntry(label: "Beta", level: 2, pageIndex: 1),
        ])
        #expect(doc.tableOfContents == [
            .init(id: 0, title: "Alpha", level: 1),
            .init(id: 2, title: "Beta", level: 2),
        ])
    }

    @Test func insertsAnOutlineHeadingWhenNoTextMatchesIt() {
        let doc = StructureBuilder.build(lines: [
            line("Body text on the first page.", 12),
            line("Body text on the second page.", 13, page: 1),
        ], fallbackTitle: "T", outline: [OutlineEntry(label: "Chapter 2", level: 1, pageIndex: 1)])
        #expect(doc.blocks.map(\.text) == ["Body text on the first page.", "Chapter 2", "Body text on the second page."])
        #expect(doc.tableOfContents == [.init(id: 1, title: "Chapter 2", level: 1)])
    }

    // MARK: - Footnotes

    private func kinds(_ doc: ReaderDocument) -> [String] {
        doc.blocks.map {
            switch $0.kind {
            case .heading: "heading"
            case .paragraph: "paragraph"
            case .footnote(let marker): "footnote \(marker)"
            }
        }
    }

    @Test func liftsAFootnoteOutOfTheBodyAndRejoinsTheParagraphItInterrupted() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 24), line("Body text that starts on page one and", 12), line("1 A footnote about it.", 8),
            line("continues on page two.", 12, page: 1), line("Beta", 24, page: 1),
            line("Final body text for the second section.", 12, page: 1),
        ], fallbackTitle: "T")

        #expect(doc.blocks.map(\.text) == [
            "Alpha", "Body text that starts on page one and continues on page two.",
            "A footnote about it.", "Beta", "Final body text for the second section.",
        ])
        #expect(kinds(doc) == ["heading", "paragraph", "footnote 1", "heading", "paragraph"])
        #expect(doc.blocks.map(\.id) == Array(0..<5))
    }

    @Test func eachMarkerStartsItsOwnFootnote() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 24), line("Body text on the first page of it.", 12),
            line("* First note.", 8), line("† Second note.", 8),
            line("Beta", 24, page: 1), line("Body text on the second page of it.", 12, page: 1),
        ], fallbackTitle: "T")
        #expect(kinds(doc) == ["heading", "paragraph", "footnote *", "footnote †", "heading", "paragraph"])
        #expect(doc.blocks[2].text == "First note.")
    }

    @Test func unmarkedSmallLinesContinueTheFootnoteAbove() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 24), line("Body text on the first page of it.", 12),
            line("1 A note that runs", 8), line("onto a second line.", 8),
            line("Beta", 24, page: 1), line("Body text on the second page of it.", 12, page: 1),
        ], fallbackTitle: "T")
        #expect(doc.blocks[2] == Block(id: 2, kind: .footnote(marker: "1"), text: "A note that runs onto a second line."))
    }

    @Test func smallTextWithoutAMarkerStaysInTheBody() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 24), line("Body text on the first page of it.", 12), line("Figure caption text", 8),
            line("Beta", 24, page: 1), line("Body text on the second page of it.", 12, page: 1),
        ], fallbackTitle: "T")
        #expect(kinds(doc) == ["heading", "paragraph", "paragraph", "heading", "paragraph"])
    }

    @Test func smallTextThatDoesNotEndThePageStaysInTheBody() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 24), line("Body text on the first page of it.", 12),
            line("1 A small aside", 8), line("More body text after the aside.", 12),
            line("Beta", 24, page: 1), line("Body text on the second page of it.", 12, page: 1),
        ], fallbackTitle: "T")
        #expect(!kinds(doc).contains { $0.hasPrefix("footnote") })
    }

    @Test func aMarkerNeedsToBeAStandaloneNumber() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 24), line("Body text on the first page of it.", 12), line("1999 was a small year", 8),
            line("Beta", 24, page: 1), line("Body text on the second page of it.", 12, page: 1),
        ], fallbackTitle: "T")
        #expect(!kinds(doc).contains { $0.hasPrefix("footnote") })
    }

    @Test func footnotesInTheLastSectionGoAtTheEndOfTheDocument() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 24), line("Body text on the first page of it.", 12),
            line("Beta", 24, page: 1), line("Body text on the second page of it.", 12, page: 1),
            line("1 The last note.", 8, page: 1),
        ], fallbackTitle: "T")
        #expect(kinds(doc) == ["heading", "paragraph", "heading", "paragraph", "footnote 1"])
    }

    @Test func outlineSectionsGetTheirFootnotesBeforeTheNextHeading() {
        let doc = StructureBuilder.build(lines: [
            line("Alpha", 12), line("Alpha body text that is long enough to be body text.", 12), line("1 A note.", 8),
            line("Beta", 12, page: 1), line("Beta body text that is long enough to be body text.", 12, page: 1),
        ], fallbackTitle: "T", outline: [
            OutlineEntry(label: "Alpha", level: 1, pageIndex: 0),
            OutlineEntry(label: "Beta", level: 1, pageIndex: 1),
        ])
        #expect(kinds(doc) == ["heading", "paragraph", "footnote 1", "heading", "paragraph"])
    }
}
