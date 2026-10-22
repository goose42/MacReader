import Foundation
import Testing
@testable import MacReaderKit

struct LibraryStoreTests {
    private func makeLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePDF(named name: String, pages: [String], title: String? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try PDFFixtures.makePDF(pages: pages, title: title).write(to: url)
        return url
    }

    @Test func itemRoundTripsThroughJSON() throws {
        let item = LibraryItem(id: UUID(), title: "T", sourceFileName: "a.pdf", dateAdded: Date(timeIntervalSince1970: 100), pageCount: 3)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(LibraryItem.self, from: encoder.encode(item)) == item)
    }

    @Test func ingestCreatesItemFolderWithThreeFiles() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(pdfAt: writePDF(named: "doc.pdf", pages: ["Hello world"], title: "Greeting"))

        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        for name in ["original.pdf", "content.txt", "metadata.json"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
        }
        #expect(item.title == "Greeting")
        #expect(try store.text(for: item).contains("Hello world"))
    }

    @Test func titleFallsBackToFileName() throws {
        let store = LibraryStore(root: try makeLibrary())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("My Paper.pdf")
        try PDFFixtures.makePDF(pages: ["Body"]).write(to: url)
        #expect(try store.ingest(pdfAt: url).title == "My Paper")
    }

    @Test func itemsAreSortedNewestFirstAndSkipMalformedFolders() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let first = try store.ingest(pdfAt: writePDF(named: "a.pdf", pages: ["A"]))
        let second = try store.ingest(pdfAt: writePDF(named: "b.pdf", pages: ["B"]))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Items/garbage"), withIntermediateDirectories: true)

        #expect(try store.items().map(\.id) == [second.id, first.id])
    }

    @Test func failedIngestLeavesNoPartialFolder() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let blank = try writePDF(named: "blank.pdf", pages: [""])
        #expect(throws: PDFTextExtractor.Failure.noText) { try store.ingest(pdfAt: blank) }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Items").path)) ?? []
        #expect(leftovers.isEmpty)
    }
}
