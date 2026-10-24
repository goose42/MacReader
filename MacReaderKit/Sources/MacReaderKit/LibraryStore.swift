import Foundation

/// Reads and writes the on-disk library: `Items/<uuid>/{original.pdf, content.txt, metadata.json}`.
public struct LibraryStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    private var itemsDirectory: URL { root.appendingPathComponent("Items", isDirectory: true) }

    private func folder(for id: UUID) -> URL {
        itemsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    @discardableResult
    public func ingest(pdfAt url: URL) throws -> LibraryItem {
        let data = try Data(contentsOf: url)
        let extracted = try PDFTextExtractor.extract(
            from: data, fallbackTitle: url.deletingPathExtension().lastPathComponent)

        let item = LibraryItem(
            id: UUID(),
            title: extracted.document.title,
            sourceFileName: url.lastPathComponent,
            dateAdded: Date(),
            pageCount: extracted.pageCount)

        // Build in a staging folder, then move into place so failures leave nothing behind.
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try data.write(to: staging.appendingPathComponent("original.pdf"))
        try write(extracted.document, images: extracted.images, into: staging)
        try Self.encoder.encode(item).write(to: staging.appendingPathComponent("metadata.json"))

        try fileManager.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        try fileManager.moveItem(at: staging, to: folder(for: item.id))
        return item
    }

    /// All items, newest first. Folders with missing or unreadable metadata are skipped.
    public func items() throws -> [LibraryItem] {
        guard FileManager.default.fileExists(atPath: itemsDirectory.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(
            at: itemsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("metadata.json")) }
            .compactMap { try? Self.decoder.decode(LibraryItem.self, from: $0) }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    /// Permanently removes the item's folder (PDF, text, and metadata) from the library. Missing items are ignored.
    public func delete(_ item: LibraryItem) throws {
        let folder = folder(for: item.id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// The item's structured document. Items imported before `document.json` existed, or saved by an older
    /// extraction format, are rebuilt from their original PDF, and the result is saved so this only happens once.
    public func document(for item: LibraryItem) throws -> ReaderDocument {
        let folder = folder(for: item.id)
        if let data = try? Data(contentsOf: folder.appendingPathComponent("document.json")),
           let document = try? JSONDecoder().decode(ReaderDocument.self, from: data),
           document.formatVersion >= ReaderDocument.currentFormatVersion {
            return document
        }
        let pdf = try Data(contentsOf: folder.appendingPathComponent("original.pdf"))
        let extracted = try PDFTextExtractor.extract(from: pdf, fallbackTitle: item.title)
        try write(extracted.document, images: extracted.images, into: folder)
        return extracted.document
    }

    /// The sentence the reader last stopped on, or nil if none was saved or the file is unreadable.
    public func readingPosition(for item: LibraryItem) -> SentenceNavigator.Position? {
        guard let data = try? Data(contentsOf: positionURL(for: item)) else { return nil }
        return try? JSONDecoder().decode(SentenceNavigator.Position.self, from: data)
    }

    /// Saved apart from `document.json`, which is regenerated when the extraction format changes.
    public func saveReadingPosition(_ position: SentenceNavigator.Position, for item: LibraryItem) throws {
        try JSONEncoder().encode(position).write(to: positionURL(for: item), options: .atomic)
    }

    private func positionURL(for item: LibraryItem) -> URL {
        folder(for: item.id).appendingPathComponent("position.json")
    }

    /// Where a figure of the item's document is saved.
    public func imageURL(for item: LibraryItem, named name: String) -> URL {
        folder(for: item.id).appendingPathComponent("Images", isDirectory: true).appendingPathComponent(name)
    }

    public func text(for item: LibraryItem) throws -> String {
        try String(contentsOf: folder(for: item.id).appendingPathComponent("content.txt"), encoding: .utf8)
    }

    /// Writes `document.json`, the plaintext `content.txt` derived from it, and any rendered figures.
    private func write(_ document: ReaderDocument, images: [String: Data], into folder: URL) throws {
        if !images.isEmpty {
            let directory = folder.appendingPathComponent("Images", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, data) in images { try data.write(to: directory.appendingPathComponent(name)) }
        }
        try document.plainText.write(to: folder.appendingPathComponent("content.txt"), atomically: true, encoding: .utf8)
        try JSONEncoder().encode(document).write(to: folder.appendingPathComponent("document.json"), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
