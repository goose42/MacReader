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

    @Test func ingestCreatesItemFolderWithItsFiles() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(pdfAt: writePDF(named: "doc.pdf", pages: ["Hello world"], title: "Greeting"))

        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        for name in ["original.pdf", "content.txt", "document.json", "metadata.json"] {
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

    @Test func documentForReturnsTheStructuredDocument() throws {
        let store = LibraryStore(root: try makeLibrary())
        let item = try store.ingest(pdfAt: writePDF(named: "doc.pdf", pages: ["Some readable body text."]))
        let document = try store.document(for: item)
        #expect(document.plainText == "Some readable body text.")
    }

    @Test func documentForRebuildsItemsImportedBeforeDocumentJSONExisted() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(pdfAt: writePDF(named: "doc.pdf", pages: ["Legacy body text."]))
        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("document.json"))
        try "stale flattened text".write(to: folder.appendingPathComponent("content.txt"), atomically: true, encoding: .utf8)

        let document = try store.document(for: item)

        #expect(document.plainText == "Legacy body text.")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("document.json").path))
        #expect(try store.text(for: item) == "Legacy body text.")
    }

    @Test func documentForRebuildsDocumentsSavedBeforeSentenceRangesExisted() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(pdfAt: writePDF(named: "doc.pdf", pages: ["First one. Second one."]))
        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        let legacy = #"{"title":"Old","blocks":[{"id":0,"kind":{"paragraph":{}},"text":"First one. Second one."}]}"#
        try legacy.write(to: folder.appendingPathComponent("document.json"), atomically: true, encoding: .utf8)

        let document = try store.document(for: item)

        #expect(document.blocks.first?.sentences == [0..<10, 11..<22])
        let saved = try JSONDecoder().decode(ReaderDocument.self, from: Data(contentsOf: folder.appendingPathComponent("document.json")))
        #expect(saved == document)
    }

    @Test func rebuildsADocumentSavedByAnOlderFormatVersion() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(pdfAt: writePDF(named: "doc.pdf", pages: ["Fresh body text."]))
        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        let old = #"{"title":"Old","blocks":[{"id":0,"kind":{"paragraph":{}},"text":"Stale text"}]}"#
        try old.write(to: folder.appendingPathComponent("document.json"), atomically: true, encoding: .utf8)

        let document = try store.document(for: item)

        #expect(document.plainText == "Fresh body text.")
        #expect(document.formatVersion == ReaderDocument.currentFormatVersion)
        #expect(try store.text(for: item) == "Fresh body text.")
    }

    @Test func deleteRemovesTheItemFolderEntirely() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let keep = try store.ingest(pdfAt: writePDF(named: "keep.pdf", pages: ["Keep me"]))
        let drop = try store.ingest(pdfAt: writePDF(named: "drop.pdf", pages: ["Drop me"]))

        try store.delete(drop)

        #expect(try store.items().map(\.id) == [keep.id])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Items/\(drop.id.uuidString)").path))
    }

    @Test func deletingAnAlreadyMissingItemDoesNotThrow() throws {
        let store = LibraryStore(root: try makeLibrary())
        let item = try store.ingest(pdfAt: writePDF(named: "a.pdf", pages: ["A"]))
        try store.delete(item)
        try store.delete(item)
    }

    @Test func savesRenderedImagesNextToTheDocument() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Visual.pdf")
        try PDFFixtures.makeVisualPDF().write(to: url)
        let item = try store.ingest(pdfAt: url)

        let document = try store.document(for: item)
        let name = try #require(document.imageNames.first)
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: item, named: name).path))
    }

    @Test func restoresMissingImagesWhenRebuildingAnOldDocument() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Visual2.pdf")
        try PDFFixtures.makeVisualPDF().write(to: url)
        let item = try store.ingest(pdfAt: url)
        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Images"))
        let old = #"{"title":"Old","blocks":[{"id":0,"kind":{"paragraph":{}},"text":"Stale text"}]}"#
        try old.write(to: folder.appendingPathComponent("document.json"), atomically: true, encoding: .utf8)

        let document = try store.document(for: item)

        let name = try #require(document.imageNames.first)
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: item, named: name).path))
    }
}
