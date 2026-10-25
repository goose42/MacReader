import Foundation
import Testing
@testable import MacReaderKit

struct LibraryItemKindTests {
    @Test func booksAreTheirOwnKinds() throws {
        let item = LibraryItem(
            id: UUID(), title: "T", sourceFileName: "t.epub", dateAdded: Date(timeIntervalSince1970: 5), pageCount: 0,
            sourceKind: .epub, author: "Jane Author")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let decoded = try decoder.decode(LibraryItem.self, from: encoder.encode(item))
        #expect(decoded == item)
        #expect(decoded.sourceKind == .epub)
        #expect(decoded.author == "Jane Author")
        #expect(LibraryItem.SourceKind(rawValue: "mobi") == .mobi)
    }

    @Test func itemsSavedBeforeBooksHaveNoAuthor() throws {
        let json = #"{"id": "\#(UUID().uuidString)", "title": "T", "sourceFileName": "a.html", "dateAdded": 0, "pageCount": 0, "sourceKind": "html", "siteName": "Example"}"#
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: Data(json.utf8))
        #expect(decoded.author == nil)
        #expect(decoded.siteName == "Example")
    }
}

struct LibraryStoreEbookTests {
    private func makeLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func result(
        format: EbookExtractor.Format = .epub, title: String = "A Book", author: String? = "Jane Author", images: [String: Data] = [:]
    ) -> EbookExtractor.Result {
        var blocks: [ReaderDocument.Block] = [.init(id: 0, kind: .paragraph, text: "Once upon a time.")]
        if let name = images.keys.first { blocks.append(.init(id: 1, kind: .image(name: name, aspectRatio: 1), text: "")) }
        return EbookExtractor.Result(
            document: ReaderDocument(title: title, blocks: blocks, metadata: ArticleMetadata(byline: author)), images: images, format: format)
    }

    private func file(_ name: String, _ data: Data = Data("book bytes".utf8)) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    @Test func ingestKeepsTheBookAndItsDocument() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let source = try file("Moby Dick.epub")
        let item = try store.ingest(ebookAt: source, extracted: result(title: "Moby-Dick"))

        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        for name in ["original.epub", "content.txt", "document.json", "metadata.json"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), "\(name)")
        }
        #expect(try Data(contentsOf: folder.appendingPathComponent("original.epub")) == Data("book bytes".utf8))
        #expect(item.title == "Moby-Dick")
        #expect(item.sourceKind == .epub)
        #expect(item.author == "Jane Author")
        #expect(item.sourceFileName.hasSuffix("Moby Dick.epub"))
        #expect(item.pageCount == 0)
        #expect(try store.text(for: item).contains("Once upon a time."))
        #expect(try store.items().map(\.id) == [item.id])
        #expect(try store.document(for: item).title == "Moby-Dick")
    }

    @Test func aKindleBookIsKeptAsAMobi() throws {
        let store = LibraryStore(root: try makeLibrary())
        let item = try store.ingest(ebookAt: try file("book.azw3"), extracted: result(format: .mobi))
        #expect(item.sourceKind == .mobi)
        #expect(store.originalURL(for: item).lastPathComponent == "original.mobi")
        #expect(FileManager.default.fileExists(atPath: store.originalURL(for: item).path))
    }

    @Test func anUnpackedBookIsCopiedAsAFolder() throws {
        let store = LibraryStore(root: try makeLibrary())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub", isDirectory: true)
        try EPUBFixture.write(EPUBFixture.Spec(), to: folder)
        let item = try store.ingest(ebookAt: folder, extracted: result())

        let copy = store.originalURL(for: item)
        #expect(copy.lastPathComponent == "original.epub")
        #expect(FileManager.default.fileExists(atPath: copy.appendingPathComponent("META-INF/container.xml").path))
        #expect(try EPUBContainer(contentsOf: copy).packagePath() == "OEBPS/content.opf")
    }

    @Test func picturesAreSavedWhereTheReaderLooksForThem() throws {
        let store = LibraryStore(root: try makeLibrary())
        let item = try store.ingest(ebookAt: try file("a.epub"), extracted: result(images: ["book-1.png": Data([1, 2, 3])]))
        #expect(try Data(contentsOf: store.imageURL(for: item, named: "book-1.png")) == Data([1, 2, 3]))
    }

    @Test func aFailedIngestLeavesNothingBehind() throws {
        let store = LibraryStore(root: try makeLibrary())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        #expect(throws: (any Error).self) { try store.ingest(ebookAt: missing, extracted: result()) }
        #expect(try store.items().isEmpty)
    }

    @Test func anOutOfDateBookIsToBeReadAgainFromItsOriginal() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(ebookAt: try file("a.epub"), extracted: result())
        let stale = #"{"formatVersion": 1, "title": "Old", "blocks": []}"#
        try Data(stale.utf8).write(to: root.appendingPathComponent("Items/\(item.id.uuidString)/document.json"))
        #expect(throws: LibraryStore.Failure.needsRebuild) { try store.document(for: item) }

        try store.refresh(item, with: result(title: "New Title"))
        #expect(try store.document(for: item).title == "New Title")
    }

    @Test func eachKindHasItsOwnOriginal() throws {
        let store = LibraryStore(root: try makeLibrary())
        func name(_ kind: LibraryItem.SourceKind) -> String {
            store.originalURL(for: LibraryItem(id: UUID(), title: "", sourceFileName: "", dateAdded: Date(), pageCount: 0, sourceKind: kind)).lastPathComponent
        }
        #expect(name(.pdf) == "original.pdf")
        #expect(name(.html) == "original.html")
        #expect(name(.epub) == "original.epub")
        #expect(name(.mobi) == "original.mobi")
    }
}
