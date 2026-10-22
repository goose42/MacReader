import Foundation
import Testing
@testable import MacReaderKit

struct LibraryLocationTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "LibraryLocationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func resolveReturnsNilWhenNothingSaved() {
        #expect(LibraryLocation(defaults: makeDefaults()).resolve() == nil)
    }

    @Test func saveThenResolveReturnsSameFolder() throws {
        let location = LibraryLocation(defaults: makeDefaults())
        let folder = try makeFolder()
        try location.save(folder)
        #expect(location.resolve()?.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
    }

    @Test func resolveReturnsNilWhenFolderWasDeleted() throws {
        let location = LibraryLocation(defaults: makeDefaults())
        let folder = try makeFolder()
        try location.save(folder)
        try FileManager.default.removeItem(at: folder)
        #expect(location.resolve() == nil)
    }

    @Test func clearForgetsSavedFolder() throws {
        let location = LibraryLocation(defaults: makeDefaults())
        try location.save(try makeFolder())
        location.clear()
        #expect(location.resolve() == nil)
    }
}
