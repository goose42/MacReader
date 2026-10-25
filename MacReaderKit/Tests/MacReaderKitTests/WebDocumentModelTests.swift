import Foundation
import Testing
@testable import MacReaderKit

struct WebDocumentModelTests {
    @Test func listItemsAndQuotesAreReadingStopsButCodeAndCaptionsAreNot() {
        let item = ReaderDocument.Block(id: 0, kind: .listItem(marker: "•", depth: 0), text: "One. Two.")
        let quote = ReaderDocument.Block(id: 1, kind: .quote, text: "A wise remark. Another.")
        let code = ReaderDocument.Block(id: 2, kind: .code, text: "let x = 1. let y = 2.")
        let caption = ReaderDocument.Block(id: 3, kind: .caption, text: "A figure. Shown here.")
        #expect(item.sentences.count == 2)
        #expect(quote.sentences.count == 2)
        #expect(code.sentences.isEmpty)
        #expect(caption.sentences.isEmpty)
    }

    @Test func plainTextPrefixesListMarkers() {
        let document = ReaderDocument(title: "T", blocks: [
            .init(id: 0, kind: .paragraph, text: "Intro."),
            .init(id: 1, kind: .listItem(marker: "1.", depth: 0), text: "First"),
            .init(id: 2, kind: .listItem(marker: "•", depth: 1), text: "Nested"),
            .init(id: 3, kind: .quote, text: "Quoted"),
        ])
        #expect(document.plainText == "Intro.\n\n1. First\n\n    • Nested\n\nQuoted")
    }

    @Test func metadataSurvivesAJSONRoundTrip() throws {
        let metadata = ArticleMetadata(
            byline: "Ada Lovelace", siteName: "Notes", publishedDate: Date(timeIntervalSince1970: 1_000_000),
            sourceURL: URL(string: "https://example.com/a"), language: "en", isRightToLeft: false, excerpt: "Hi")
        let document = ReaderDocument(title: "T", blocks: [], metadata: metadata)
        let decoded = try JSONDecoder().decode(ReaderDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.metadata == metadata)
    }

    @Test func documentsSavedWithoutMetadataStillDecode() throws {
        let json = #"{"formatVersion": 6, "title": "Old", "blocks": []}"#
        let decoded = try JSONDecoder().decode(ReaderDocument.self, from: Data(json.utf8))
        #expect(decoded.metadata == nil)
    }

    @Test func itemsSavedBeforeWebPagesAreFromPDFs() throws {
        let json = #"{"id": "\#(UUID().uuidString)", "title": "T", "sourceFileName": "a.pdf", "dateAdded": 0, "pageCount": 2}"#
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: Data(json.utf8))
        #expect(decoded.sourceKind == .pdf)
        #expect(decoded.siteName == nil)
    }

    @Test func aWebItemKeepsItsKindAndSiteName() throws {
        let item = LibraryItem(id: UUID(), title: "T", sourceFileName: "a.html", dateAdded: Date(timeIntervalSince1970: 5), pageCount: 0, sourceKind: .html, siteName: "Example")
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}
