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
        let extracted = try PDFTextExtractor.extract(from: data)

        let item = LibraryItem(
            id: UUID(),
            title: extracted.title ?? url.deletingPathExtension().lastPathComponent,
            sourceFileName: url.lastPathComponent,
            dateAdded: Date(),
            pageCount: extracted.pageCount)

        // Build in a staging folder, then move into place so failures leave nothing behind.
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try data.write(to: staging.appendingPathComponent("original.pdf"))
        try extracted.text.write(to: staging.appendingPathComponent("content.txt"), atomically: true, encoding: .utf8)
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

    public func text(for item: LibraryItem) throws -> String {
        try String(contentsOf: folder(for: item.id).appendingPathComponent("content.txt"), encoding: .utf8)
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
