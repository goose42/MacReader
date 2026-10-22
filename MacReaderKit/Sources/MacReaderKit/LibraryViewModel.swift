import Foundation
import Observation

@MainActor @Observable
public final class LibraryViewModel {
    public enum State: Equatable { case noLibrary, empty, loaded }

    public private(set) var state: State = .noLibrary
    public private(set) var items: [LibraryItem] = []
    public private(set) var selectedDocument: ReaderDocument?
    public private(set) var errorMessage: String?

    private let location: LibraryLocation
    private var store: LibraryStore?
    private var scopedFolder: URL?

    public init(location: LibraryLocation = LibraryLocation()) {
        self.location = location
        if let saved = location.resolve() { open(saved) }
    }

    public func chooseLibrary(_ url: URL) {
        // Access must be started before bookmarking: the sandbox rejects bookmarks for unopened scoped URLs.
        open(url)
        do {
            try location.save(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addPDFs(_ urls: [URL]) {
        guard let store else { return }
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try store.ingest(pdfAt: url)
            } catch {
                failures.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
        }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        reload()
    }

    public func select(_ item: LibraryItem) {
        do {
            selectedDocument = try store?.document(for: item)
        } catch {
            selectedDocument = nil
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ url: URL) {
        scopedFolder?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        scopedFolder = url
        store = LibraryStore(root: url)
        selectedDocument = nil
        errorMessage = nil
        reload()
    }

    private func reload() {
        do {
            items = try store?.items() ?? []
            state = items.isEmpty ? .empty : .loaded
        } catch {
            items = []
            state = .empty
            errorMessage = error.localizedDescription
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? PDFTextExtractor.Failure {
        case .unreadable: "Couldn't read this PDF."
        case .noText: "No text found (it may be a scanned image)."
        case nil: error.localizedDescription
        }
    }
}
