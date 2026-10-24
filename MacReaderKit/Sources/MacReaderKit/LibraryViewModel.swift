import Foundation
import Observation

@MainActor @Observable
public final class LibraryViewModel {
    public enum State: Equatable { case noLibrary, empty, loaded }

    public private(set) var state: State = .noLibrary
    public private(set) var items: [LibraryItem] = []
    public private(set) var selectedDocument: ReaderDocument?
    /// The sentence the selected document was last read up to, or nil if it hasn't been read.
    public private(set) var selectedPosition: SentenceNavigator.Position?
    public private(set) var errorMessage: String?

    private var selectedItemID: LibraryItem.ID?
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
            selectedItemID = item.id
            selectedDocument = try store?.document(for: item)
            selectedPosition = store?.readingPosition(for: item)
        } catch {
            selectedDocument = nil
            selectedPosition = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Remembers where the reader is in the selected document. A failed write is ignored: it happens on every step.
    public func saveReadingPosition(_ position: SentenceNavigator.Position) {
        guard let store, let item = items.first(where: { $0.id == selectedItemID }) else { return }
        selectedPosition = position
        try? store.saveReadingPosition(position, for: item)
    }

    /// Where a figure of the selected document is saved, or nil when nothing is selected.
    public func selectedImageURL(named name: String) -> URL? {
        guard let store, let item = items.first(where: { $0.id == selectedItemID }), selectedDocument != nil else { return nil }
        return store.imageURL(for: item, named: name)
    }

    public func delete(_ item: LibraryItem) {
        do {
            try store?.delete(item)
            if selectedItemID == item.id { selectedDocument = nil; selectedPosition = nil }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    private func open(_ url: URL) {
        scopedFolder?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        scopedFolder = url
        store = LibraryStore(root: url)
        selectedItemID = nil
        selectedDocument = nil
        selectedPosition = nil
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
