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
}
