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

    @Test func numbersHeadingsFromEyebrowLabelsAndInlinePrefixes() {
        let body = "body body body body body body body body body body."
        let doc = StructureBuilder.build(lines: [
            line("MODULE 1", 10), line("First topic", 24), line(body, 12),
            line("2.1 Second topic", 24, page: 1), line(body, 12, page: 1),
        ], fallbackTitle: "T")
        #expect(doc.tableOfContents == [
            .init(id: 0, title: "First topic", level: 1, numbering: .init(label: "Module 1", placement: .eyebrow)),
            .init(id: 2, title: "Second topic", level: 1, numbering: .init(label: "2.1", placement: .inline)),
        ])
    }

    @Test func anchorsAnOutlineEntryToANumberedLineWithoutDuplicatingTheHeading() {
        let doc = StructureBuilder.build(lines: [
            line("1 Introduction", 12), line("intro body text that is long enough to be body text.", 12),
        ], fallbackTitle: "T", outline: [OutlineEntry(label: "Introduction", level: 1, pageIndex: 0)])
        #expect(doc.blocks.map(\.text) == ["Introduction", "intro body text that is long enough to be body text."])
        #expect(doc.tableOfContents == [.init(id: 0, title: "Introduction", level: 1, numbering: .init(label: "1", placement: .inline))])
    }
}
