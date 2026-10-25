import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct LibraryViewModelEbookTests {
    private func makeViewModel() throws -> LibraryViewModel {
        let suite = "LibraryViewModelEbookTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = LibraryViewModel(location: LibraryLocation(defaults: defaults))
        model.chooseLibrary(try makeFolder())
        return model
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        let url = try makeFolder().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private var book: EPUBFixture.Spec {
        var spec = EPUBFixture.Spec()
        spec.title = "The Whale"
        spec.authors = ["Herman Melville"]
        spec.chapters = [.init(file: "ch1.xhtml", navTitle: "Loomings", body: "<h2>Loomings</h2><p>Call me Ishmael.</p>")]
        return spec
    }

    @Test func anEPUBIsAddedAndRead() async throws {
        let model = try makeViewModel()
        await model.addDocuments([try write(EPUBFixture.archive(book), named: "Moby Dick.epub")])

        let item = try #require(model.items.first)
        #expect(model.items.count == 1)
        #expect(item.sourceKind == .epub)
        #expect(item.title == "The Whale")
        #expect(item.author == "Herman Melville")
        #expect(model.errorMessage == nil)
        #expect(model.state == .loaded)

        model.select(item)
        #expect(model.selectedDocument?.plainText.contains("Call me Ishmael.") == true)
        #expect(model.selectedPageURL == nil)
    }

    @Test func anUnpackedEPUBFolderIsABookNotAnAttachment() async throws {
        let model = try makeViewModel()
        let folder = try makeFolder().appendingPathComponent("Moby Dick.epub", isDirectory: true)
        try EPUBFixture.write(book, to: folder)
        await model.addDocuments([folder])
        #expect(model.items.map(\.sourceKind) == [.epub])
        #expect(model.errorMessage == nil)
    }

    @Test func aKindleBookIsAddedAndRead() async throws {
        let model = try makeViewModel()
        var spec = MOBIFixture.Spec(title: "Kindle Book")
        spec.text = Data(#"<html><body><p align="center"><font size="7">One</font></p><p>Some words here.</p></body></html>"#.utf8)
        spec.exth = [MOBIFixture.exth(100, "Ann Author")]
        await model.addDocuments([try write(MOBIFixture.build(spec), named: "book.mobi")])

        let item = try #require(model.items.first)
        #expect(item.sourceKind == .mobi)
        #expect(item.author == "Ann Author")
        model.select(item)
        #expect(model.selectedDocument?.tableOfContents.map(\.title) == ["One"])
    }

    @Test func aKF8BookIsAddedWhateverItsExtension() async throws {
        let model = try makeViewModel()
        var spec = KF8Fixture.Spec()
        spec.parts = [.init(fragments: ["<h1>One</h1><p>Words.</p>"], title: "One")]
        await model.addDocuments([try write(KF8Fixture.build(spec), named: "book.azw3"), try write(KF8Fixture.build(spec), named: "book.prc")])
        #expect(model.items.map(\.sourceKind) == [.mobi, .mobi])
    }

    @Test func booksPDFsAndPagesCanBeAddedTogether() async throws {
        let model = try makeViewModel()
        let pdf = try write(PDFFixtures.makePDF(pages: ["Some text on a page."]), named: "a.pdf")
        let page = try write(Data("<html><head><title>Post</title></head><body><article><p>\(String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 12))</p><p>\(String(repeating: "Pack my box with five dozen liquor jugs. ", count: 12))</p></article></body></html>".utf8), named: "Post.html")
        await model.addDocuments([pdf, try write(EPUBFixture.archive(book), named: "b.epub"), page])
        #expect(Set(model.items.map(\.sourceKind)) == [.pdf, .epub, .html])
        #expect(model.errorMessage == nil)
    }

    @Test func knowsWhichFilesTheLibraryCanTake() throws {
        for name in ["a.pdf", "A.PDF", "a.html", "a.htm", "a.epub", "a.mobi", "a.azw", "a.AZW3", "a.prc"] {
            #expect(LibraryViewModel.canAdd(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
        }
        for name in ["a.txt", "a.docx", "a.zip", "a"] {
            #expect(!LibraryViewModel.canAdd(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
        }
        // Folders ride along with a page's images, or are an unpacked book.
        #expect(LibraryViewModel.canAdd(try makeFolder()))
    }

    // MARK: Failures

    @Test func aProtectedBookIsRefusedWithAnExplanation() async throws {
        let model = try makeViewModel()
        var spec = book
        spec.extraFiles["META-INF/rights.xml"] = Data("<rights/>".utf8)
        await model.addDocuments([try write(EPUBFixture.archive(spec), named: "Locked.epub")])
        #expect(model.items.isEmpty)
        #expect(model.errorMessage?.contains("Locked.epub") == true)
        #expect(model.errorMessage?.contains("DRM") == true)
    }

    @Test func somethingThatIsNotABookSaysSo() async throws {
        let model = try makeViewModel()
        await model.addDocuments([try write(Data("not a zip".utf8), named: "notes.epub"), try write(Data("hello".utf8), named: "notes.txt")])
        #expect(model.items.isEmpty)
        let message = try #require(model.errorMessage)
        #expect(message.contains("notes.epub"))
        #expect(message.contains("notes.txt"))
        #expect(message.contains("ebook"))
    }

    @Test func aBookWithNoTextSaysSo() async throws {
        let model = try makeViewModel()
        var spec = book
        spec.chapters = [.init(file: "ch1.xhtml", navTitle: "Empty", body: "<div></div>")]
        spec.navigationOverride = EPUBFixture.xhtml("<p>x</p>")
        await model.addDocuments([try write(EPUBFixture.archive(spec), named: "Empty.epub")])
        #expect(model.items.isEmpty)
        #expect(model.errorMessage?.contains("No text found in this book") == true)
    }

    // MARK: Rebuilding

    @Test func aStaleBookIsReadAgainWhenSelected() async throws {
        let library = try makeFolder()
        let suite = "LibraryViewModelEbookTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = LibraryViewModel(location: LibraryLocation(defaults: defaults))
        model.chooseLibrary(library)
        await model.addDocuments([try write(EPUBFixture.archive(book), named: "Moby Dick.epub")])
        let item = model.items[0]

        let stale = #"{"formatVersion": 1, "title": "Old", "blocks": []}"#
        try Data(stale.utf8).write(to: library.appendingPathComponent("Items/\(item.id.uuidString)/document.json"))
        model.select(item)
        await model.rebuilding?.value

        #expect(model.selectedDocument?.title == "The Whale")
        #expect(model.selectedDocument?.plainText.contains("Call me Ishmael.") == true)
        #expect(model.errorMessage == nil)
    }
}
