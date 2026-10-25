import Foundation

/// Reads an ebook into the structured document the reader shows, the way `PDFTextExtractor` reads a PDF.
public enum EbookExtractor {
    public enum Failure: Error, Equatable {
        /// Not a book of a kind MacReader reads, or damaged.
        case unreadable
        /// Locked with DRM, which can't be opened without the seller's keys.
        case drmProtected
        /// A recognisable ebook format that isn't supported.
        case unsupported
        case noText
    }

    public enum Format: String, Sendable {
        case epub, mobi
    }

    public struct Result {
        public let document: ReaderDocument
        /// Pictures the document refers to, keyed by file name.
        public let images: [String: Data]
        public let format: Format

        init(document: ReaderDocument, images: [String: Data], format: Format) {
            self.document = document
            self.images = images
            self.format = format
        }
    }

    /// Which kind of book `url` is, by what it holds rather than what it is called: an EPUB is a ZIP (or a folder with
    /// `META-INF/container.xml`), and a Kindle book is a Palm database of type `BOOKMOBI`.
    public static func format(of url: URL) -> Format? {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("META-INF/container.xml").path) ? .epub : nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url), let header = try? handle.read(upToCount: 68) else { return nil }
        try? handle.close()
        if header.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .epub }
        if header.count >= 68, ["BOOKMOBI", "TEXtREAd"].contains(String(decoding: header[60..<68], as: UTF8.self)) { return .mobi }
        return nil
    }

    @MainActor
    public static func extract(from url: URL) async throws -> Result {
        switch format(of: url) {
        case .epub: try await EPUBExtractor.extract(from: url)
        case .mobi, nil: throw Failure.unsupported
        }
    }
}
