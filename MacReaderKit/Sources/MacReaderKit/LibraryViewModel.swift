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
    /// True while a web page is being read, which takes a moment.
    public private(set) var isWorking = false

    private var selectedItemID: LibraryItem.ID?
    private let location: LibraryLocation
    private var store: LibraryStore?
    private var scopedFolder: URL?
    /// The extraction started by selecting a web page saved by an older format; tests wait on it.
    private(set) var rebuilding: Task<Void, Never>?

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

    /// Adds PDFs and saved web pages. Folders selected beside a page (its "…_files" folder) are only there to give
    /// the app access to its images.
    public func addDocuments(_ urls: [URL]) async {
        guard let store else { return }
        let scopes = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { for (url, scoped) in scopes where scoped { url.stopAccessingSecurityScopedResource() } }
        isWorking = true
        defer { isWorking = false }

        var messages: [String] = []
        var missingImages = 0
        for url in urls where !Self.isFolder(url) {
            do {
                switch url.pathExtension.lowercased() {
                case "pdf":
                    try store.ingest(pdfAt: url)
                case "html", "htm":
                    let extracted = try await HTMLTextExtractor.extract(pageAt: url)
                    missingImages += extracted.missingImageCount
                    try store.ingest(htmlAt: url, extracted: extracted)
                default:
                    messages.append("\(url.lastPathComponent): Only PDFs and saved web pages can be added.")
                }
            } catch {
                messages.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
        }
        if missingImages > 0 {
            messages.append("Some images couldn’t be loaded. To include them, select the page’s “…_files” folder along with the page.")
        }
        errorMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
        reload()
    }

    public func select(_ item: LibraryItem) {
        rebuilding?.cancel()
        selectedItemID = item.id
        do {
            selectedDocument = try store?.document(for: item)
            selectedPosition = store?.readingPosition(for: item)
        } catch LibraryStore.Failure.needsRebuild {
            selectedDocument = nil
            selectedPosition = nil
            rebuild(item)
        } catch {
            selectedDocument = nil
            selectedPosition = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Reads a web page saved by an older format again from its saved copy.
    private func rebuild(_ item: LibraryItem) {
        guard let store else { return }
        isWorking = true
        rebuilding = Task {
            defer { isWorking = false }
            do {
                let extracted = try await HTMLTextExtractor.extract(pageAt: store.originalPageURL(for: item))
                try store.refresh(item, with: extracted)
                guard !Task.isCancelled, selectedItemID == item.id else { return }
                selectedDocument = try store.document(for: item)
                selectedPosition = store.readingPosition(for: item)
            } catch {
                guard !Task.isCancelled, selectedItemID == item.id else { return }
                errorMessage = Self.describe(error)
            }
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

    private static func isFolder(_ url: URL) -> Bool {
        url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? HTMLTextExtractor.Failure {
            switch failure {
            case .unreadable: return "Couldn't read this page."
            case .noArticle: return "Couldn't find an article on this page."
            }
        }
        switch error as? PDFTextExtractor.Failure {
        case .unreadable: return "Couldn't read this PDF."
        case .noText: return "No text found (it may be a scanned image)."
        case nil: return error.localizedDescription
        }
    }
}
