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
        /// How many pictures the page points at on disk that couldn't be read, usually because the folder holding
        /// them wasn't opened along with the page.
        public let missingImageCount: Int

        init(document: ReaderDocument, originalHTML: Data, resourcesFolder: URL?, images: [String: Data], missingImageCount: Int = 0) {
            self.document = document
            self.originalHTML = originalHTML
            self.resourcesFolder = resourcesFolder
            self.images = images
            self.missingImageCount = missingImageCount
        }
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

        let resolved = MetadataResolver.resolve(
            payload.metadata, readability: article, savedFromURL: HTMLSource.savedFromURL(in: html) ?? HTMLSource.whereFromURL(at: url))
        let title = resolved.title ?? url.deletingPathExtension().lastPathComponent
        let missing = MissingImages()
        let built = HTMLStructureBuilder.build(from: article.content, title: title) { loadImage($0, missing: missing) }
        guard !built.blocks.isEmpty else { throw Failure.noArticle }

        return Result(
            document: ReaderDocument(title: title, blocks: built.blocks, metadata: ArticleMetadata(
                byline: resolved.byline, siteName: resolved.siteName, publishedDate: resolved.publishedDate,
                sourceURL: resolved.sourceURL, language: resolved.language, isRightToLeft: resolved.isRightToLeft,
                excerpt: resolved.excerpt)),
            originalHTML: data,
            resourcesFolder: HTMLSource.resourcesFolder(for: url),
            images: built.images,
            missingImageCount: missing.addresses.count)
    }

    private final class MissingImages {
        var addresses: Set<String> = []
    }

    /// An image's bytes from an inline `data:` address or a file next to the page; pictures that live only on the
    /// web are left out, since reading never touches the network.
    private static func loadImage(_ address: String, missing: MissingImages) -> Data? {
        if address.hasPrefix("data:") {
            guard let comma = address.firstIndex(of: ",") else { return nil }
            let header = address[..<comma]
            let payload = String(address[address.index(after: comma)...])
            return header.hasSuffix(";base64") ? Data(base64Encoded: payload) : payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        guard let url = URL(string: address), url.isFileURL else { return nil }
        if let data = try? Data(contentsOf: url) { return data }
        missing.addresses.insert(address)
        return nil
    }
}
