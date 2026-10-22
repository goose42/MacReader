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

    private func at(_ text: String, y: CGFloat, page: Int = 0, size: Double = 12, x: CGFloat = 72, width: CGFloat = 300) -> TextLine {
        TextLine(text: text, fontSize: size, pageIndex: page, bounds: CGRect(x: x, y: y, width: width, height: CGFloat(size)))
    }

    /// A line of monospaced text, 7pt per character, starting `indent` characters in from x = 72.
    private func code(_ text: String, y: CGFloat, indent: Int = 0) -> TextLine {
        at(text, y: y, x: 72 + CGFloat(indent) * 7, width: CGFloat(text.count) * 7)
    }

    private let noteBox = PageBox(pageIndex: 0, rect: CGRect(x: 60, y: 560, width: 480, height: 100))

    @Test func pullsTextInsideABoxOutOfTheFlowIntoACallout() {
        let doc = StructureBuilder.build(lines: [
            at("Before the box and some more words.", y: 700),
            at("Boxed note", y: 620, width: 440), at("continues here.", y: 600),
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

    @Test func keepsLineBreaksInBoxesWhoseLinesDoNotFillTheBox() {
        let doc = StructureBuilder.build(lines: [
            at("Body text above the box.", y: 700),
            code("def add(a, b):", y: 620), code("return a + b", y: 600, indent: 4), code("print(add(1, 2))", y: 580),
        ], fallbackTitle: "T", boxes: [noteBox])
        #expect(doc.blocks.last?.kind == .callout)
        #expect(doc.blocks.last?.text == "def add(a, b):\n    return a + b\nprint(add(1, 2))")
    }

    @Test func restoresNestedIndentationRelativeToTheLeastIndentedLine() {
        let doc = StructureBuilder.build(lines: [
            code("class A:", y: 640, indent: 2), code("def f(self):", y: 620, indent: 4), code("return 1", y: 600, indent: 6),
        ], fallbackTitle: "T", boxes: [noteBox])
        #expect(doc.blocks.first?.text == "class A:\n  def f(self):\n    return 1")
    }

    // MARK: - Tables

    private let pricing = TableGrid(pageIndex: 0, columns: [72...200, 202...400], rules: [500, 450], top: 536, bottom: 380)

    private var pricingLines: [TextLine] {
        [
            at("Intro paragraph with some words.", y: 700),
            at("Module", y: 520, x: 80, width: 60), at("Target", y: 520, x: 220, width: 60),
            at("Python", y: 470, x: 80, width: 60), at("2 days", y: 470, x: 220, width: 60),
            at("APIs", y: 420, x: 80, width: 60), at("1.5 days", y: 420, x: 220, width: 60),
            at("and more", y: 404, x: 220, width: 60),
            at("Closing paragraph with some words.", y: 200),
        ]
    }

    @Test func buildsATableBlockFromCellsPlacedByPosition() {
        let doc = StructureBuilder.build(lines: pricingLines, fallbackTitle: "T", tables: [pricing])

        #expect(doc.blocks.map(\.kind) == [
            .paragraph,
            .table(.init(rows: [["Module", "Target"], ["Python", "2 days"], ["APIs", "1.5 days and more"]], hasHeader: true)),
            .paragraph,
        ])
        #expect(doc.blocks[1].text == "Module\tTarget\nPython\t2 days\nAPIs\t1.5 days and more")
    }

    @Test func keepsTableTextOutOfTheParagraphs() {
        let doc = StructureBuilder.build(lines: pricingLines, fallbackTitle: "T", tables: [pricing])
        #expect(doc.blocks.filter { $0.kind == .paragraph }.map(\.text) == [
            "Intro paragraph with some words.", "Closing paragraph with some words.",
        ])
    }

    @Test func leavesEmptyCellsEmpty() {
        let lines = [at("Module", y: 520, x: 80, width: 60), at("Target", y: 520, x: 220, width: 60), at("Python", y: 470, x: 80, width: 60)]
        let doc = StructureBuilder.build(lines: lines, fallbackTitle: "T", tables: [pricing])
        #expect(doc.blocks.first?.kind == .table(.init(rows: [["Module", "Target"], ["Python", ""]], hasHeader: true)))
    }

    @Test func fallsBackToTheFlowWhenTheGridHasASingleColumn() {
        let single = TableGrid(pageIndex: 0, columns: [72...400], rules: [500, 450], top: 536, bottom: 380)
        let doc = StructureBuilder.build(lines: pricingLines, fallbackTitle: "T", tables: [single])
        #expect(!doc.blocks.contains { if case .table = $0.kind { true } else { false } })
    }

    @Test func fallsBackToTheFlowWhenNoTextFallsInTheTable() {
        let doc = StructureBuilder.build(lines: [at("Only a paragraph here.", y: 700)], fallbackTitle: "T", tables: [pricing])
        #expect(doc.blocks.map(\.kind) == [.paragraph])
    }

    @Test func keepsNumbersThatStandAloneInACell() {
        // Outside a table a line that is only digits is a page number, but in a cell it is the data.
        let lines = [
            at("Year", y: 520, x: 80, width: 60), at("Count", y: 520, x: 220, width: 60),
            at("2024", y: 470, x: 80, width: 60), at("17", y: 470, x: 220, width: 60),
        ]
        let doc = StructureBuilder.build(lines: lines, fallbackTitle: "T", tables: [pricing])
        #expect(doc.blocks.first?.kind == .table(.init(rows: [["Year", "Count"], ["2024", "17"]], hasHeader: true)))
    }

    @Test func keepsANumberInsideABox() {
        let doc = StructureBuilder.build(lines: [at("42", y: 620, width: 440)], fallbackTitle: "T", boxes: [noteBox])
        #expect(doc.blocks.map(\.kind) == [.callout])
        #expect(doc.blocks.first?.text == "42")
    }

    // MARK: - Tables across pages

    private let firstPart = TableGrid(pageIndex: 0, columns: [72...200, 202...400], rules: [500, 450], top: 536, bottom: 40)

    private func secondPart(extraTop: CGFloat = 740) -> TableGrid {
        TableGrid(pageIndex: 1, columns: [72...200, 202...400], rules: [700, 650], top: extraTop, bottom: 600, continuesPrevious: true)
    }

    private var firstPartLines: [TextLine] {
        [
            at("Module", y: 520, x: 80, width: 60), at("Target", y: 520, x: 220, width: 60),
            at("Python", y: 470, x: 80, width: 60), at("2 days", y: 470, x: 220, width: 60),
            at("APIs", y: 420, x: 80, width: 60), at("1.5 days", y: 420, x: 220, width: 60),
        ]
    }

    @Test func foldsWrappedTextSpillingOntoTheNextPageIntoTheLastRowsCell() {
        let lines = firstPartLines + [
            at("and more", y: 712, page: 1, x: 220, width: 60),
            at("Ruby", y: 670, page: 1, x: 80, width: 60), at("3 days", y: 670, page: 1, x: 220, width: 60),
            at("Go", y: 620, page: 1, x: 80, width: 60), at("1 day", y: 620, page: 1, x: 220, width: 60),
        ]
        let doc = StructureBuilder.build(lines: lines, fallbackTitle: "T", tables: [firstPart, secondPart()])

        #expect(doc.blocks.map(\.kind) == [.table(.init(
            rows: [["Module", "Target"], ["Python", "2 days"], ["APIs", "1.5 days and more"], ["Ruby", "3 days"], ["Go", "1 day"]],
            hasHeader: true))])
    }

    @Test func dropsAHeaderRepeatedAtTheTopOfTheNextPage() {
        let lines = firstPartLines + [
            at("Module", y: 712, page: 1, x: 80, width: 60), at("Target", y: 712, page: 1, x: 220, width: 60),
            at("Ruby", y: 670, page: 1, x: 80, width: 60), at("3 days", y: 670, page: 1, x: 220, width: 60),
        ]
        let doc = StructureBuilder.build(lines: lines, fallbackTitle: "T", tables: [firstPart, secondPart()])
        guard case .table(let table)? = doc.blocks.first?.kind else {
            Issue.record("no table")
            return
        }
        #expect(table.rows.map { $0[0] } == ["Module", "Python", "APIs", "Ruby"])
    }

    @Test func appendsAFullRowAtTheTopOfTheNextPageAsARow() {
        let lines = firstPartLines + [
            at("Perl", y: 712, page: 1, x: 80, width: 60), at("4 days", y: 712, page: 1, x: 220, width: 60),
            at("Ruby", y: 670, page: 1, x: 80, width: 60), at("3 days", y: 670, page: 1, x: 220, width: 60),
        ]
        let doc = StructureBuilder.build(lines: lines, fallbackTitle: "T", tables: [firstPart, secondPart()])
        guard case .table(let table)? = doc.blocks.first?.kind else {
            Issue.record("no table")
            return
        }
        #expect(table.rows.map { $0[0] } == ["Module", "Python", "APIs", "Perl", "Ruby"])
        #expect(table.hasHeader)
    }
}
