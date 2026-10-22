import Foundation
import Testing
@testable import MacReaderKit

struct ReaderDocumentTests {
    private let sample = ReaderDocument(title: "Doc", blocks: [
        .init(id: 0, kind: .heading(level: 1), text: "Intro"),
        .init(id: 1, kind: .paragraph, text: "Body one."),
        .init(id: 2, kind: .heading(level: 2), text: "Detail"),
        .init(id: 3, kind: .paragraph, text: "Body two."),
    ])

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(sample)
        #expect(try JSONDecoder().decode(ReaderDocument.self, from: data) == sample)
    }

    @Test func tableOfContentsListsOnlyHeadingsWithLevelsAndBlockIDs() {
        #expect(sample.tableOfContents == [
            .init(id: 0, title: "Intro", level: 1),
            .init(id: 2, title: "Detail", level: 2),
        ])
    }

    @Test func plainTextSeparatesBlocksWithBlankLines() {
        #expect(sample.plainText == "Intro\n\nBody one.\n\nDetail\n\nBody two.")
    }

    @Test func paragraphsRecordTheirSentenceRanges() {
        let block = ReaderDocument.Block(id: 0, kind: .paragraph, text: "Hi. Yo.")
        #expect(block.sentences == [0..<3, 4..<7])
    }

    @Test func headingsAreASingleSentence() {
        let block = ReaderDocument.Block(id: 0, kind: .heading(level: 1), text: "Dr. Smith. Part Two")
        #expect(block.sentences == [0..<19])
    }

    @Test func footnotesHaveNoSentenceStops() {
        let block = ReaderDocument.Block(id: 0, kind: .footnote(marker: "1"), text: "See above. Really.")
        #expect(block.sentences.isEmpty)
    }

    @Test func footnotesRoundTripAndStayOutOfTheContents() throws {
        let doc = ReaderDocument(title: "Doc", blocks: sample.blocks + [
            .init(id: 4, kind: .footnote(marker: "*"), text: "A note."),
        ])
        let data = try JSONEncoder().encode(doc)
        #expect(try JSONDecoder().decode(ReaderDocument.self, from: data) == doc)
        #expect(doc.tableOfContents == sample.tableOfContents)
        #expect(doc.plainText.hasSuffix("\n\nA note."))
    }

    @Test func blocksSavedWithoutSentencesDeriveThemFromTheirText() throws {
        let json = #"{"title":"T","blocks":[{"id":0,"kind":{"paragraph":{}},"text":"Hi. Yo."}]}"#
        let decoded = try JSONDecoder().decode(ReaderDocument.self, from: Data(json.utf8))
        #expect(decoded.blocks[0].sentences == [0..<3, 4..<7])
    }

    private let numbered = ReaderDocument(title: "Doc", blocks: [
        .init(id: 0, kind: .heading(level: 1), text: "Intro", numbering: .init(label: "1", placement: .inline)),
        .init(id: 1, kind: .paragraph, text: "Body."),
        .init(id: 2, kind: .heading(level: 2), text: "Detail", numbering: .init(label: "1.1", placement: .inline)),
        .init(id: 3, kind: .heading(level: 1), text: "Next", numbering: .init(label: "2", placement: .inline)),
        .init(id: 4, kind: .heading(level: 1), text: "Unnumbered"),
    ])

    @Test func plainTextIncludesHeadingNumbers() {
        #expect(numbered.plainText == "1 Intro\n\nBody.\n\n1.1 Detail\n\n2 Next\n\nUnnumbered")
    }

    @Test func tableOfContentsCarriesNumbering() {
        #expect(numbered.tableOfContents.first?.numbering == .init(label: "1", placement: .inline))
    }

    @Test func sectionBreaksMarkShallowestNumberedHeadingsExceptTheFirstBlock() {
        #expect(numbered.sectionBreaks == [3])
    }

    @Test func documentsWithoutAFormatVersionDecodeAsVersionOne() throws {
        let json = #"{"title":"Old","blocks":[{"id":0,"kind":{"paragraph":{}},"text":"Hi"}]}"#
        let decoded = try JSONDecoder().decode(ReaderDocument.self, from: Data(json.utf8))
        #expect(decoded.formatVersion == 1)
        #expect(ReaderDocument(title: "New", blocks: []).formatVersion == ReaderDocument.currentFormatVersion)
    }

    private let visual = ReaderDocument(title: "Doc", blocks: [
        .init(id: 0, kind: .heading(level: 1), text: "Intro"),
        .init(id: 1, kind: .callout, text: "Remember to breathe."),
        .init(id: 2, kind: .image(name: "p1-1.png", aspectRatio: 1.5), text: ""),
        .init(id: 3, kind: .paragraph, text: "After."),
    ])

    @Test func calloutsAndImagesRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(visual)
        #expect(try JSONDecoder().decode(ReaderDocument.self, from: data) == visual)
    }

    @Test func plainTextKeepsCalloutTextAndSkipsImages() {
        #expect(visual.plainText == "Intro\n\nRemember to breathe.\n\nAfter.")
    }

    @Test func imageNamesListsEveryFigureTheDocumentReferences() {
        #expect(visual.imageNames == ["p1-1.png"])
    }

    private let withTable = ReaderDocument(title: "Doc", blocks: [
        .init(id: 0, kind: .paragraph, text: "Before."),
        .table(id: 1, rows: [["Module", "Target"], ["Python", "2 days"], ["APIs", "1.5 days"]], hasHeader: true),
        .init(id: 2, kind: .paragraph, text: "After."),
    ])

    @Test func tablesRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(withTable)
        #expect(try JSONDecoder().decode(ReaderDocument.self, from: data) == withTable)
    }

    @Test func tableBlocksCarryTabSeparatedTextForPlainText() {
        #expect(withTable.blocks[1].text == "Module\tTarget\nPython\t2 days\nAPIs\t1.5 days")
        #expect(withTable.plainText == "Before.\n\nModule\tTarget\nPython\t2 days\nAPIs\t1.5 days\n\nAfter.")
    }

    @Test func aTableIsNotAHeadingInTheContents() {
        #expect(withTable.tableOfContents.isEmpty)
    }
}
