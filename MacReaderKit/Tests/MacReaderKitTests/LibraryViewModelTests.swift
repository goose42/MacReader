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

    @Test func selectingItemLoadsItsText() throws {
        let model = makeViewModel()
        model.chooseLibrary(try makeFolder())
        model.addPDFs([try writePDF("a.pdf", pages: ["Readable words"])])
        model.select(model.items[0])
        #expect(model.selectedText?.contains("Readable words") == true)
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
}
