import Foundation
import Testing
@testable import MacReaderKit

/// The same book, *Alice's Adventures in Wonderland* from Project Gutenberg, in each format (see `Fixtures/Ebook`).
@MainActor
struct RealBookTests {
    static let chapterTitles = [
        "CHAPTER I. Down the Rabbit-Hole", "CHAPTER II. The Pool of Tears", "CHAPTER III. A Caucus-Race and a Long Tale",
        "CHAPTER IV. The Rabbit Sends in a Little Bill", "CHAPTER V. Advice from a Caterpillar", "CHAPTER VI. Pig and Pepper",
        "CHAPTER VII. A Mad Tea-Party", "CHAPTER VIII. The Queen’s Croquet-Ground", "CHAPTER IX. The Mock Turtle’s Story",
        "CHAPTER X. The Lobster Quadrille", "CHAPTER XI. Who Stole the Tarts?", "CHAPTER XII. Alice’s Evidence",
    ]

    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Ebook"))
    }

    @Test func theEPUBReadsAsABook() async throws {
        let result = try await EbookExtractor.extract(from: fixture("alice.epub"))
        let document = result.document

        #expect(result.format == .epub)
        #expect(document.title == "Alice's Adventures in Wonderland")
        #expect(document.metadata?.byline == "Lewis Carroll")
        #expect(document.metadata?.language == "en")
        #expect(document.tableOfContents.map(\.title).filter { $0.hasPrefix("CHAPTER") } == Self.chapterTitles)
        #expect(document.plainText.contains("Alice was beginning to get very tired of sitting by her sister"))
        #expect(document.plainText.contains("Down, down, down."))

        // The cover is the one picture, and the paragraphs can be read a sentence at a time.
        #expect(result.images.count == 1)
        #expect(document.imageNames.count == 1)
        let falling = try #require(document.blocks.first { $0.text.contains("Down, down, down.") })
        #expect(falling.sentences.count > 1)
    }

    @Test func theKindleBookReadsAsABook() async throws {
        let result = try await EbookExtractor.extract(from: fixture("alice-mobi6.mobi"))
        let document = result.document

        #expect(result.format == .mobi)
        #expect(document.title == "Alice's Adventures in Wonderland")
        #expect(document.metadata?.byline == "Lewis Carroll")
        #expect(document.metadata?.language == "en")
        #expect(document.metadata?.publishedDate != nil)

        // The chapter headings are paragraphs set in a large font; each is a heading, once.
        #expect(document.tableOfContents.map(\.title).filter { $0.hasPrefix("CHAPTER") } == Self.chapterTitles)
        #expect(document.plainText.contains("Alice was beginning to get very tired of sitting by her sister"))

        // The contents page the file ends with is gone, and the book's text still ends with its licence.
        #expect(!document.blocks.contains { $0.text == "Table of Contents" })
        #expect(document.blocks.last?.text.contains("Project Gutenberg") == true)
    }

    @Test func theKF8BookReadsAsABook() async throws {
        let result = try await EbookExtractor.extract(from: fixture("alice-kf8.azw3"))
        let document = result.document

        #expect(result.format == .mobi)
        #expect(document.title == "Alice's Adventures in Wonderland")
        #expect(document.metadata?.byline == "Lewis Carroll")
        #expect(document.metadata?.language == "en")
        #expect(document.tableOfContents.map(\.title).filter { $0.hasPrefix("CHAPTER") } == Self.chapterTitles)
        #expect(document.plainText.contains("Alice was beginning to get very tired of sitting by her sister"))

        // The cover is addressed as kindle:embed:0001, the first picture record.
        #expect(result.images.count == 1)
        #expect(document.imageNames.count == 1)
        let falling = try #require(document.blocks.first { $0.text.contains("Down, down, down.") })
        #expect(falling.sentences.count > 1)
    }

    @Test func allThreeFormatsAgreeOnTheText() async throws {
        let epub = try await EbookExtractor.extract(from: fixture("alice.epub")).document
        let mobi = try await EbookExtractor.extract(from: fixture("alice-mobi6.mobi")).document
        let kf8 = try await EbookExtractor.extract(from: fixture("alice-kf8.azw3")).document

        // The same story, however it was packaged: every word a reader would read from the opening line to "THE END".
        // Each format lays out scene breaks, verse and indentation in its own way, so only the words are compared.
        func story(_ document: ReaderDocument) -> [String] {
            let start = document.blocks.firstIndex { $0.text.hasPrefix("Alice was beginning to get very tired") } ?? 0
            let end = document.blocks.firstIndex { $0.text == "THE END" } ?? document.blocks.count
            return document.blocks[start..<end].filter { block in
                switch block.kind {
                case .image, .table: false
                default: true
                }
            }.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }.filter { !$0.allSatisfy { $0 == "*" } }
        }
        #expect(story(epub).count == 26_374)
        #expect(story(mobi) == story(epub))
        #expect(story(kf8) == story(epub))
    }
}
