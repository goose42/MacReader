import Foundation

/// Reads a saved web page into a structured document, the way `PDFTextExtractor` reads a PDF.
public enum HTMLTextExtractor {
    public enum Failure: Error, Equatable {
        case unreadable, noArticle
        /// The web view could not load or run the page; the text says why.
        case webViewFailed(String)
    }

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
        let resourcesFolder = HTMLSource.resourcesFolder(for: url)
        let downloads = resourcesFolder.map(downloadedImages(in:)) ?? [:]
        let missing = MissingImages()
        let read = try await read(
            html: html, baseURL: url, savedFrom: HTMLSource.savedFromURL(in: html) ?? HTMLSource.whereFromURL(at: url),
            fallbackTitle: url.deletingPathExtension().lastPathComponent
        ) { loadImage($0, downloads: downloads, missing: missing) }

        return Result(
            document: read.document, originalHTML: data, resourcesFolder: resourcesFolder, images: read.images,
            missingImageCount: missing.addresses.count)
    }

    /// Reads a page fetched from the web. Its pictures are downloaded now, because reading never touches the network
    /// later, and saved with a manifest in an `original_files` folder, where `extract(pageAt:)` finds them again.
    /// `download` fetches one picture; by default it is a plain request that refuses non-images and very large files.
    @MainActor
    public static func extract(
        fetched snapshot: WebPageFetcher.Snapshot, download: (@Sendable (URL) async throws -> Data)? = nil
    ) async throws -> Result {
        let html = snapshot.html
        let savedFrom = HTMLSource.savedFromURL(in: html) ?? snapshot.finalURL
        let fallbackTitle = snapshot.finalURL.host() ?? "Web Page"

        let wanted = Addresses()
        _ = try await read(html: html, baseURL: snapshot.finalURL, savedFrom: savedFrom, fallbackTitle: fallbackTitle) {
            wanted.insert($0)
            return nil
        }

        let downloaded = await downloadImages(
            wanted.ordered.prefix(maximumDownloads).compactMap { address in
                webAddress(address, relativeTo: snapshot.finalURL).map { (address, $0) }
            }, with: download ?? downloadImage)
        let folder = try saveDownloads(downloaded.images)

        let missing = MissingImages()
        let read = try await read(html: html, baseURL: snapshot.finalURL, savedFrom: savedFrom, fallbackTitle: fallbackTitle) {
            if let data = loadImage($0, downloads: downloaded.images, missing: missing) { return data }
            if downloaded.failed.contains($0) { missing.addresses.insert($0) }
            return nil
        }
        return Result(
            document: read.document, originalHTML: Data(html.utf8), resourcesFolder: folder, images: read.images,
            missingImageCount: missing.addresses.count)
    }

    /// The article in `html` as a document, with pictures supplied by `loadImage`.
    @MainActor
    private static func read(
        html: String, baseURL: URL, savedFrom: URL?, fallbackTitle: String, loadImage: @escaping (String) -> Data?
    ) async throws -> (document: ReaderDocument, images: [String: Data]) {
        let payload: ExtractionPayload
        do {
            payload = try await WebPageExtractor.extract(html: html, baseURL: baseURL)
        } catch {
            throw Failure.webViewFailed(String(describing: error))
        }
        guard let choice = ContentArbiter.choose(payload) else { throw Failure.noArticle }

        let resolved = MetadataResolver.resolve(payload.metadata, readability: payload.readability, savedFromURL: savedFrom)
        let title = resolved.title ?? fallbackTitle
        let content = BoilerplateFilter.filter(choice.content, byline: resolved.byline, publishedDate: resolved.publishedDate)
        let built = HTMLStructureBuilder.build(from: content, title: title, loadImage: loadImage)
        guard !built.blocks.isEmpty else { throw Failure.noArticle }

        let document = ReaderDocument(title: title, blocks: built.blocks, metadata: ArticleMetadata(
            byline: resolved.byline, siteName: resolved.siteName, publishedDate: resolved.publishedDate,
            sourceURL: resolved.sourceURL, language: resolved.language, isRightToLeft: resolved.isRightToLeft,
            excerpt: resolved.excerpt))
        return (document, built.images)
    }

    private final class MissingImages {
        var addresses: Set<String> = []
    }

    /// Name of the file in a page's resources folder that maps the web addresses of pictures downloaded when the
    /// page was fetched to the files holding them.
    static let imageManifestName = "images.json"

    /// Web address to image bytes, read from the manifest in `folder`; empty when the page wasn't fetched from the web.
    private static func downloadedImages(in folder: URL) -> [String: Data] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(imageManifestName)),
              let manifest = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return manifest.compactMapValues { try? Data(contentsOf: folder.appendingPathComponent($0)) }
    }

    /// An image's bytes from an inline `data:` address, a file next to the page, or a picture downloaded when the
    /// page was fetched; pictures that live only on the web are left out, since reading never touches the network.
    private static func loadImage(_ address: String, downloads: [String: Data], missing: MissingImages) -> Data? {
        if let downloaded = downloads[address] { return downloaded }
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

    private final class Addresses {
        private(set) var ordered: [String] = []
        private var seen: Set<String> = []
        func insert(_ address: String) { if seen.insert(address).inserted { ordered.append(address) } }
    }

    /// The most pictures downloaded for one page, and the largest one accepted.
    private static let maximumDownloads = 60
    private static let maximumImageBytes = 10_000_000

    /// `address` as an http(s) URL, resolved against the page it appeared on; nil for inline and file addresses.
    private static func webAddress(_ address: String, relativeTo page: URL) -> URL? {
        guard let url = URL(string: address, relativeTo: page)?.absoluteURL, ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    /// Fetches the pictures concurrently. `images` holds the bytes by address as the page wrote it; `failed` the
    /// addresses that couldn't be fetched.
    private static func downloadImages(
        _ pictures: [(address: String, url: URL)], with download: @escaping @Sendable (URL) async throws -> Data
    ) async -> (images: [String: Data], failed: Set<String>) {
        await withTaskGroup(of: (String, Data?).self) { group in
            for picture in pictures {
                group.addTask { (picture.address, try? await download(picture.url)) }
            }
            var images: [String: Data] = [:]
            var failed: Set<String> = []
            for await (address, data) in group {
                if let data { images[address] = data } else { failed.insert(address) }
            }
            return (images, failed)
        }
    }

    /// Writes the downloaded pictures and their manifest to a new `original_files` folder.
    private static func saveDownloads(_ images: [String: Data]) throws -> URL? {
        guard !images.isEmpty else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("original_files", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest: [String: String] = [:]
        for (index, entry) in images.sorted(by: { $0.key < $1.key }).enumerated() {
            let name = "\(index).png"
            try entry.value.write(to: folder.appendingPathComponent(name))
            manifest[entry.key] = name
        }
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent(imageManifestName))
        return folder
    }

    @Sendable
    private static func downloadImage(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.mimeType?.hasPrefix("image/") == true, data.count <= maximumImageBytes
        else { throw URLError(.badServerResponse) }
        return data
    }
}
