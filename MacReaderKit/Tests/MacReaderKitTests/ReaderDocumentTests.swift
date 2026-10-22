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
}
