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

    @Test func documentsSavedWithoutSentencesFailToDecode() {
        let json = #"{"title":"T","blocks":[{"id":0,"kind":{"paragraph":{}},"text":"Hi."}]}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ReaderDocument.self, from: Data(json.utf8))
        }
    }
}
