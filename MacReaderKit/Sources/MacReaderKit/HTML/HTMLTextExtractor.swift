import Foundation

/// Reads a saved web page into a structured document, the way `PDFTextExtractor` reads a PDF.
public enum HTMLTextExtractor {
    public enum Failure: Error, Equatable { case unreadable, noArticle }

    public struct Result {
        public let document: ReaderDocument
        /// The page exactly as it was saved.
        public let originalHTML: Data
        /// The folder of images and styles saved beside the page, if there is one.
        public let resourcesFolder: URL?
        /// Pictures the document refers to, keyed by file name.
        public let images: [String: Data]
    }

    @MainActor
    public static func extract(pageAt url: URL) async throws -> Result {
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        let html = HTMLSource.decode(data)
        let payload: ExtractionPayload
        do {
            payload = try await WebPageExtractor.extract(html: html, baseURL: url)
        } catch {
            throw Failure.unreadable
        }
        guard let article = payload.readability else { throw Failure.noArticle }

        let title = [article.title, payload.metadata.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? url.deletingPathExtension().lastPathComponent
        let built = HTMLStructureBuilder.build(from: article.content, title: title) { loadImage($0) }
        guard !built.blocks.isEmpty else { throw Failure.noArticle }

        return Result(
            document: ReaderDocument(title: title, blocks: built.blocks),
            originalHTML: data,
            resourcesFolder: HTMLSource.resourcesFolder(for: url),
            images: built.images)
    }

    /// An image's bytes from an inline `data:` address or a file next to the page; pictures that live only on the
    /// web are left out, since reading never touches the network.
    private static func loadImage(_ address: String) -> Data? {
        if address.hasPrefix("data:") {
            guard let comma = address.firstIndex(of: ",") else { return nil }
            let header = address[..<comma]
            let payload = String(address[address.index(after: comma)...])
            return header.hasSuffix(";base64") ? Data(base64Encoded: payload) : payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        guard let url = URL(string: address), url.isFileURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
