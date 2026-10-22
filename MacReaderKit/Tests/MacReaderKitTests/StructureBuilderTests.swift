import CoreGraphics
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

    // MARK: - Boxes and figures

    private func at(_ text: String, y: CGFloat, page: Int = 0, size: Double = 12) -> TextLine {
        TextLine(text: text, fontSize: size, pageIndex: page, bounds: CGRect(x: 72, y: y, width: 300, height: CGFloat(size)))
    }

    private let noteBox = PageBox(pageIndex: 0, rect: CGRect(x: 60, y: 560, width: 480, height: 100))

    @Test func pullsTextInsideABoxOutOfTheFlowIntoACallout() {
        let doc = StructureBuilder.build(lines: [
            at("Before the box and some more words.", y: 700),
            at("Boxed note", y: 620), at("continues here.", y: 600),
            at("After the box and some more words.", y: 400),
        ], fallbackTitle: "T", boxes: [noteBox])
        #expect(doc.blocks.map(\.kind) == [.paragraph, .callout, .paragraph])
        #expect(doc.blocks.map(\.text) == [
            "Before the box and some more words.", "Boxed note continues here.", "After the box and some more words.",
        ])
    }

    @Test func ignoresABoxThatHoldsNoText() {
        let doc = StructureBuilder.build(lines: [at("Only body text here.", y: 700)], fallbackTitle: "T", boxes: [noteBox])
        #expect(doc.blocks.map(\.kind) == [.paragraph])
    }

    @Test func placesAFigureWhereItSitsBetweenTheLines() {
        let figure = Figure(pageIndex: 0, rect: CGRect(x: 72, y: 380, width: 200, height: 100), name: "p1-1.png")
        let doc = StructureBuilder.build(lines: [
            at("Above the figure, words.", y: 700), at("Below the figure, words.", y: 300),
        ], fallbackTitle: "T", figures: [figure])
        #expect(doc.blocks.map(\.kind) == [.paragraph, .image(name: "p1-1.png", aspectRatio: 2), .paragraph])
        #expect(doc.imageNames == ["p1-1.png"])
    }

    @Test func putsAFigureAfterTheLastLineWhenNothingFollowsIt() {
        let figure = Figure(pageIndex: 0, rect: CGRect(x: 72, y: 100, width: 100, height: 100), name: "p1-1.png")
        let doc = StructureBuilder.build(lines: [at("Only text on the page.", y: 700)], fallbackTitle: "T", figures: [figure])
        #expect(doc.blocks.map(\.kind) == [.paragraph, .image(name: "p1-1.png", aspectRatio: 1)])
    }

    @Test func keepsBoxedLinesOutOfHeadingDetection() {
        let doc = StructureBuilder.build(lines: [
            at("Body text of the document goes here.", y: 700),
            at("Big boxed words", y: 620, size: 30),
            at("More body text of the document goes here.", y: 400),
        ], fallbackTitle: "T", boxes: [noteBox])
        #expect(doc.tableOfContents.isEmpty)
        #expect(doc.blocks.map(\.kind) == [.paragraph, .callout, .paragraph])
    }

    @Test func leavesAnInlineHighlightOnASingleLineInTheFlow() {
        let pill = PageBox(pageIndex: 0, rect: CGRect(x: 150, y: 612, width: 120, height: 16))
        let doc = StructureBuilder.build(lines: [
            at("Use inline code in a sentence here.", y: 620),
            at("and the sentence carries on after it.", y: 600),
        ], fallbackTitle: "T", boxes: [pill])
        #expect(doc.blocks.map(\.kind) == [.paragraph])
    }

    @Test func keepsAWideSingleLineBoxAsACallout() {
        let banner = PageBox(pageIndex: 0, rect: CGRect(x: 60, y: 612, width: 480, height: 24))
        let doc = StructureBuilder.build(lines: [
            at("Body text above the banner.", y: 700), at("Heads up: read this first.", y: 620),
        ], fallbackTitle: "T", boxes: [banner])
        #expect(doc.blocks.map(\.kind) == [.paragraph, .callout])
    }
}
