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

    /// Why the last attempt to add a web address failed, for the sheet that asked; nil once an attempt starts.
    public private(set) var webPageError: String?

    private let fetchPage: @MainActor (URL) async throws -> HTMLTextExtractor.Result

    /// `fetchPage` loads a web address and reads it; by default it opens the page in a browser and downloads its pictures.
    public init(
        location: LibraryLocation = LibraryLocation(),
        fetchPage: @escaping @MainActor (URL) async throws -> HTMLTextExtractor.Result = {
            try await HTMLTextExtractor.extract(fetched: WebPageFetcher.fetch($0))
        }
    ) {
        self.location = location
        self.fetchPage = fetchPage
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

    /// Fetches the page at a typed or pasted address and adds it to the library. Returns the new item, or nil with
    /// `webPageError` set; a failure here is shown by the address sheet, not the library's alert.
    public func addWebPage(_ input: String) async -> LibraryItem? {
        guard let store else { return nil }
        webPageError = nil
        guard let address = WebAddress.parse(input) else {
            webPageError = "Enter a web address that starts with http or https."
            return nil
        }
        do {
            let extracted = try await fetchPage(address)
            let item = try store.ingest(extracted, named: WebAddress.fileName(for: extracted.document.metadata?.sourceURL ?? address))
            reload()
            return item
        } catch {
            guard !Task.isCancelled else { return nil }
            webPageError = Self.describe(error)
            return nil
        }
    }

    /// Called when the address sheet opens, so an earlier attempt's error isn't shown again.
    public func dismissWebPageError() {
        webPageError = nil
    }

    /// Called when the person closes the error alert, so it doesn't reappear on the next update.
    public func dismissError() {
        errorMessage = nil
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

    /// How much of `item` has been read, from 0 to 1, or nil unless it is the open document.
    public func progress(of item: LibraryItem) -> Double? {
        guard item.id == selectedItemID, let selectedDocument else { return nil }
        return SentenceNavigator(document: selectedDocument, startingAt: selectedPosition).progress
    }

    public var selectedItem: LibraryItem? { items.first { $0.id == selectedItemID } }

    /// The item `offset` places from the selected one (-1 is the one above it), or nil at either end of the library.
    public func adjacentItem(_ offset: Int) -> LibraryItem? {
        guard let index = items.firstIndex(where: { $0.id == selectedItemID }), items.indices.contains(index + offset) else { return nil }
        return items[index + offset]
    }

    /// The saved copy of the selected web page, which opens in a browser to show the page as it was.
    public var selectedPageURL: URL? {
        guard let store, let item = selectedItem, item.sourceKind == .html else { return nil }
        return store.originalPageURL(for: item)
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
            case .webViewFailed(let detail): return "Couldn't read this page (\(detail))."
            }
        }
        if let failure = error as? WebPageFetcher.Failure {
            switch failure {
            case .loadFailed(let detail): return "Couldn't load this page (\(detail))."
            case .timedOut: return "The page took too long to load."
            }
        }
        switch error as? PDFTextExtractor.Failure {
        case .unreadable: return "Couldn't read this PDF."
        case .noText: return "No text found (it may be a scanned image)."
        case nil: return error.localizedDescription
        }
    }
}
