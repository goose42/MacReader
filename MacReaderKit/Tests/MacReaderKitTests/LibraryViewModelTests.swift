import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct LibraryViewModelTests {
    private func makeViewModel() -> LibraryViewModel {
        let suite = "LibraryViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return LibraryViewModel(location: LibraryLocation(defaults: defaults))
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePDF(_ name: String, pages: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try PDFFixtures.makePDF(pages: pages).write(to: url)
        return url
    }

    private func webResult(sourceURL: String = "https://example.com/2026/post") -> HTMLTextExtractor.Result {
        HTMLTextExtractor.Result(
            document: ReaderDocument(
                title: "Fetched Post", blocks: [.init(id: 0, kind: .paragraph, text: "Hello from the web.")],
                metadata: ArticleMetadata(siteName: "Example", sourceURL: URL(string: sourceURL))),
            originalHTML: Data("<html>fetched</html>".utf8), resourcesFolder: nil, images: [:])
    }

    private func makeWebViewModel(
        fetch: @escaping @MainActor (URL) async throws -> HTMLTextExtractor.Result
    ) throws -> LibraryViewModel {
        let suite = "LibraryViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = LibraryViewModel(location: LibraryLocation(defaults: defaults), fetchPage: fetch)
        model.chooseLibrary(try makeFolder())
        return model
    }

    @Test func adjacentItemStepsThroughTheLibraryAndStopsAtEitherEnd() async throws {
        let model = try makeWebViewModel { _ in webResult() }
        #expect(model.adjacentItem(1) == nil)

        _ = await model.addWebPage("example.com/a")
        _ = await model.addWebPage("example.com/b")
        _ = await model.addWebPage("example.com/c")
        #expect(model.items.count == 3)

        model.select(model.items[1])
        #expect(model.adjacentItem(-1) == model.items[0])
        #expect(model.adjacentItem(1) == model.items[2])

        model.select(model.items[0])
        #expect(model.adjacentItem(-1) == nil)
        model.select(model.items[2])
        #expect(model.adjacentItem(1) == nil)
    }

    @Test func addingAWebAddressFetchesAndStoresThePage() async throws {
        var fetched: [URL] = []
        let model = try makeWebViewModel { url in
            fetched.append(url)
            return webResult()
        }
        let item = await model.addWebPage("example.com/2026/post")

        #expect(fetched == [URL(string: "https://example.com/2026/post")!])
        #expect(item?.sourceKind == .html)
        #expect(item?.sourceFileName == "example.com/2026/post")
        #expect(model.items.map(\.id) == [item?.id])
        #expect(model.state == .loaded)
        #expect(model.webPageError == nil)
    }

    @Test func anInvalidAddressIsRejectedWithoutFetching() async throws {
        var fetched = 0
        let model = try makeWebViewModel { _ in fetched += 1; return webResult() }
        let item = await model.addWebPage("notaurl")

        #expect(item == nil)
        #expect(fetched == 0)
        #expect(model.webPageError == "Enter a web address that starts with http or https.")
        #expect(model.items.isEmpty)
    }

    @Test func aFailedFetchReportsWhyAndAddsNothing() async throws {
        let model = try makeWebViewModel { _ in throw WebPageFetcher.Failure.loadFailed("The Internet connection appears to be offline.") }
        let item = await model.addWebPage("https://example.com")

        #expect(item == nil)
        #expect(model.webPageError == "Couldn't load this page (The Internet connection appears to be offline.).")
        #expect(model.items.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func aSlowPageReportsATimeout() async throws {
        let model = try makeWebViewModel { _ in throw WebPageFetcher.Failure.timedOut }
        _ = await model.addWebPage("https://example.com")
        #expect(model.webPageError == "The page took too long to load.")
    }

    @Test func aPageWithoutAnArticleSaysSo() async throws {
        let model = try makeWebViewModel { _ in throw HTMLTextExtractor.Failure.noArticle }
        _ = await model.addWebPage("https://example.com")
        #expect(model.webPageError == "Couldn't find an article on this page.")
    }

    @Test func dismissingTheWebPageErrorClearsIt() async throws {
        let model = try makeWebViewModel { _ in webResult() }
        _ = await model.addWebPage("notaurl")
        model.dismissWebPageError()
        #expect(model.webPageError == nil)
    }

    @Test func aNewAttemptClearsThePreviousError() async throws {
        let model = try makeWebViewModel { _ in webResult() }
        _ = await model.addWebPage("notaurl")
        #expect(model.webPageError != nil)
        _ = await model.addWebPage("https://example.com/2026/post")
        #expect(model.webPageError == nil)
    }

    @Test func startsWithNoLibrary() {
        #expect(makeViewModel().state == .noLibrary)
    }

    @Test func choosingEmptyFolderYieldsEmptyState() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        #expect(model.state == .empty)
    }

    @Test func addingPDFsLoadsItems() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["A text"]), try writePDF("b.pdf", pages: ["B text"])])
        #expect(model.items.count == 2)
        #expect(model.state == .loaded)
    }

    @Test func badPDFReportsErrorButKeepsGoodOnes() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("blank.pdf", pages: [""]), try writePDF("ok.pdf", pages: ["Fine"])])
        #expect(model.items.count == 1)
        #expect(model.errorMessage != nil)
    }

    @Test func selectingItemLoadsItsDocument() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["Readable words"])])
        model.select(model.items[0])
        #expect(model.selectedDocument?.plainText.contains("Readable words") == true)
    }

    @Test func restoresSavedLibraryOnInit() throws {
        let suite = "LibraryViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = LibraryViewModel(location: LibraryLocation(defaults: defaults))
        first.chooseLibrary(try makeFolder())
        first.addPDFs([try writePDF("a.pdf", pages: ["Persisted"])])

        let second = LibraryViewModel(location: LibraryLocation(defaults: defaults))
        #expect(second.items.count == 1)
        #expect(second.state == .loaded)
    }

    @Test func deletingAnItemRemovesItFromTheLibrary() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["A text"]), try writePDF("b.pdf", pages: ["B text"])])
        let doomed = model.items[0]

        model.delete(doomed)

        #expect(!model.items.contains { $0.id == doomed.id })
        #expect(model.items.count == 1)
        #expect(model.state == .loaded)
    }

    @Test func deletingTheLastItemShowsTheEmptyState() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["A text"])])
        model.delete(model.items[0])
        #expect(model.items.isEmpty)
        #expect(model.state == .empty)
    }

    @Test func deletingTheSelectedItemClearsTheReader() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["Readable words"])])
        model.select(model.items[0])
        model.delete(model.items[0])
        #expect(model.selectedDocument == nil)
    }

    @Test func deletingADifferentItemKeepsTheSelection() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["First words"]), try writePDF("b.pdf", pages: ["Second words"])])
        let selected = model.items[0]
        model.select(selected)
        model.delete(model.items[1])
        #expect(model.selectedDocument?.plainText.contains("words") == true)
    }

    @Test func resolvesTheSelectedDocumentsImageFiles() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-visual.pdf")
        try PDFFixtures.makeVisualPDF().write(to: url)
        model.addPDFs([url])
        #expect(model.selectedImageURL(named: "p1-1.png") == nil)

        model.select(model.items[0])

        let imageURL = try #require(model.selectedImageURL(named: "p1-1.png"))
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test func readingPositionSurvivesRelaunch() throws {
        let suite = "LibraryViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let folder = try makeFolder()

        let first = LibraryViewModel(location: LibraryLocation(defaults: defaults))
        first.chooseLibrary(folder)
        first.addPDFs([try writePDF("a.pdf", pages: ["One. Two. Three."])])
        first.select(first.items[0])
        #expect(first.selectedPosition == nil)
        first.saveReadingPosition(.init(blockID: 0, sentence: 1))

        let second = LibraryViewModel(location: LibraryLocation(defaults: defaults))
        second.select(second.items[0])
        #expect(second.selectedPosition == .init(blockID: 0, sentence: 1))
    }

    @Test func progressIsOnlyReportedForTheSelectedItem() throws {
        let model = LibraryViewModel(location: LibraryLocation(defaults: UserDefaults(suiteName: "LibraryViewModelTests-\(UUID().uuidString)")!))
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["One. Two. Three."])])
        let item = model.items[0]
        model.select(item)
        model.saveReadingPosition(.init(blockID: 0, sentence: 2))

        #expect(model.progress(of: item) == 1)
        #expect(model.progress(of: LibraryItem(id: UUID(), title: "Other", sourceFileName: "o.pdf", dateAdded: .now, pageCount: 1)) == nil)
    }

    @Test func progressFollowsTheSavedPosition() throws {
        let model = LibraryViewModel(location: LibraryLocation(defaults: UserDefaults(suiteName: "LibraryViewModelTests-\(UUID().uuidString)")!))
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["One. Two. Three."])])
        model.select(model.items[0])
        #expect(model.progress(of: model.items[0]) == 0)
        model.saveReadingPosition(.init(blockID: 0, sentence: 1))
        let progress = try #require(model.progress(of: model.items[0]))
        #expect(progress > 0 && progress < 1)
    }

    // MARK: - Web pages

    private static let filler = String(repeating: "The quick brown fox jumps over the lazy dog, again and again. ", count: 10)

    private func writePage(_ name: String = "Post.html", title: String = "A Post", in folder: URL? = nil) throws -> URL {
        let directory = try folder ?? makeFolder()
        let url = directory.appendingPathComponent(name)
        try """
            <html><head><title>\(title)</title></head><body><article><p>\(Self.filler)</p><p>\(Self.filler)</p></article></body></html>
            """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func addingADocumentRoutesPDFsAndWebPages() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        await model.addDocuments([try writePDF("a.pdf", pages: ["A text"]), try writePage()])
        #expect(Set(model.items.map(\.sourceKind)) == [.pdf, .html])
        #expect(model.errorMessage == nil)
    }

    @Test func selectingAWebPageLoadsItsDocument() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        await model.addDocuments([try writePage(title: "Selected")])
        model.select(model.items[0])
        #expect(model.selectedDocument?.plainText.contains("quick brown fox") == true)
    }

    @Test func aPageWithNoArticleIsReportedAndOthersAreKept() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        let empty = try makeFolder().appendingPathComponent("empty.html")
        try "<html><body></body></html>".write(to: empty, atomically: true, encoding: .utf8)
        await model.addDocuments([empty, try writePage()])
        #expect(model.items.count == 1)
        #expect(model.errorMessage?.contains("Couldn't find an article") == true)
    }

    @Test func unsupportedFilesAreReported() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        let text = try makeFolder().appendingPathComponent("notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        await model.addDocuments([text])
        #expect(model.items.isEmpty)
        #expect(model.errorMessage?.contains("notes.txt") == true)
    }

    @Test func foldersSelectedAlongsideAPageAreNotDocuments() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        let directory = try makeFolder()
        let files = directory.appendingPathComponent("Post_files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        await model.addDocuments([try writePage(in: directory), files])
        #expect(model.items.count == 1)
        #expect(model.errorMessage == nil)
    }

    @Test func aStaleWebPageIsRebuiltWhenSelected() async throws {
        let library = try makeFolder()
        let model = makeViewModel()
        model.chooseLibrary(library)
        await model.addDocuments([try writePage(title: "Rebuilt")])
        let item = model.items[0]
        let stale = #"{"formatVersion": 1, "title": "Old", "blocks": []}"#
        try Data(stale.utf8).write(to: library.appendingPathComponent("Items/\(item.id.uuidString)/document.json"))

        model.select(item)
        await model.rebuilding?.value
        #expect(model.selectedDocument?.plainText.contains("quick brown fox") == true)
    }

    @Test func imagesThatCouldNotBeLoadedAreMentioned() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        let directory = try makeFolder()
        let url = directory.appendingPathComponent("Pics.html")
        try """
            <html><head><title>Pics</title></head><body><article><p>\(Self.filler)</p><img src="Pics_files/gone.png"><p>\(Self.filler)</p></article></body></html>
            """.write(to: url, atomically: true, encoding: .utf8)
        await model.addDocuments([url])
        #expect(model.items.count == 1)
        #expect(model.errorMessage?.contains("images") == true)
    }

    @Test func theSelectedWebPageExposesItsSavedCopyAndKind() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        await model.addDocuments([try writePDF("a.pdf", pages: ["A text"]), try writePage()])
        let page = try #require(model.items.first { $0.sourceKind == .html })
        let pdf = try #require(model.items.first { $0.sourceKind == .pdf })

        model.select(page)
        #expect(model.selectedItem == page)
        #expect(model.selectedPageURL?.lastPathComponent == "original.html")

        model.select(pdf)
        #expect(model.selectedItem == pdf)
        #expect(model.selectedPageURL == nil)
    }

    @Test func dismissingAnErrorClearsIt() async throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        let text = try makeFolder().appendingPathComponent("notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        await model.addDocuments([text])
        #expect(model.errorMessage != nil)

        model.dismissError()
        #expect(model.errorMessage == nil)
    }
}
