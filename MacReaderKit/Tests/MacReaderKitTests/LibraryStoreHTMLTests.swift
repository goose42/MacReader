import Foundation
import Testing
@testable import MacReaderKit

struct LibraryStoreHTMLTests {
    private func makeLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func extracted(
        title: String = "A Post", siteName: String? = nil, resources: URL? = nil, images: [String: Data] = [:]
    ) -> HTMLTextExtractor.Result {
        var blocks: [ReaderDocument.Block] = [.init(id: 0, kind: .paragraph, text: "Hello web.")]
        if let name = images.keys.first { blocks.append(.init(id: 1, kind: .image(name: name, aspectRatio: 1), text: "")) }
        return HTMLTextExtractor.Result(
            document: ReaderDocument(title: title, blocks: blocks, metadata: siteName.map { ArticleMetadata(siteName: $0) }),
            originalHTML: Data("<html>saved</html>".utf8), resourcesFolder: resources, images: images)
    }

    @Test func ingestCreatesAnItemFolderForAWebPage() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(htmlAt: URL(fileURLWithPath: "/tmp/My Post.html"), extracted: extracted(siteName: "Example"))

        let folder = root.appendingPathComponent("Items/\(item.id.uuidString)")
        for name in ["original.html", "content.txt", "document.json", "metadata.json"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
        }
        #expect(item.title == "A Post")
        #expect(item.sourceKind == .html)
        #expect(item.siteName == "Example")
        #expect(item.sourceFileName == "My Post.html")
        #expect(try store.text(for: item).contains("Hello web."))
        #expect(try store.items().map(\.id) == [item.id])
    }

    @Test func imagesAreSavedWhereTheReaderLooksForThem() throws {
        let store = LibraryStore(root: try makeLibrary())
        let item = try store.ingest(htmlAt: URL(fileURLWithPath: "/tmp/p.html"), extracted: extracted(images: ["web-1.png": Data([1, 2, 3])]))
        #expect(try Data(contentsOf: store.imageURL(for: item, named: "web-1.png")) == Data([1, 2, 3]))
    }

    @Test func onlyImageFilesAreCopiedFromTheResourcesFolder() throws {
        let source = try makeLibrary().appendingPathComponent("p_files", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data([1]).write(to: source.appendingPathComponent("a.jpg"))
        try Data([2]).write(to: source.appendingPathComponent("nested/b.png"))
        try Data([3]).write(to: source.appendingPathComponent("site.css"))
        try Data([4]).write(to: source.appendingPathComponent("app.js"))

        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(htmlAt: URL(fileURLWithPath: "/tmp/p.html"), extracted: extracted(resources: source))

        let copied = root.appendingPathComponent("Items/\(item.id.uuidString)/p_files")
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("nested/b.png").path))
        #expect(!FileManager.default.fileExists(atPath: copied.appendingPathComponent("site.css").path))
        #expect(!FileManager.default.fileExists(atPath: copied.appendingPathComponent("app.js").path))
    }

    @Test func aSavedWebDocumentIsReturnedAsIs() throws {
        let store = LibraryStore(root: try makeLibrary())
        let item = try store.ingest(htmlAt: URL(fileURLWithPath: "/tmp/p.html"), extracted: extracted())
        #expect(try store.document(for: item).blocks.first?.text == "Hello web.")
    }

    @Test func aStaleWebDocumentAsksToBeRebuiltAndRefreshReplacesIt() throws {
        let root = try makeLibrary()
        let store = LibraryStore(root: root)
        let item = try store.ingest(htmlAt: URL(fileURLWithPath: "/tmp/p.html"), extracted: extracted())
        let stale = #"{"formatVersion": 1, "title": "Old", "blocks": []}"#
        try Data(stale.utf8).write(to: root.appendingPathComponent("Items/\(item.id.uuidString)/document.json"))

        #expect(throws: LibraryStore.Failure.needsRebuild) { try store.document(for: item) }
        #expect(store.originalPageURL(for: item).lastPathComponent == "original.html")

        try store.refresh(item, with: extracted(title: "Fresh"))
        #expect(try store.document(for: item).title == "Fresh")
    }
}
