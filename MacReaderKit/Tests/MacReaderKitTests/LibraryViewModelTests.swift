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
}
