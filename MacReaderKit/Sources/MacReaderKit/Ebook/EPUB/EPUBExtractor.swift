import Foundation

/// Reads an EPUB: each chapter of the reading order becomes a section of one tree, which the shared builder turns into
/// blocks.
enum EPUBExtractor {
    private static let chapterTypes: Set<String> = ["application/xhtml+xml", "text/html"]

    @MainActor
    static func extract(from url: URL) async throws -> EbookExtractor.Result {
        let container: EPUBContainer
        let package: EPUBPackage
        do {
            container = try EPUBContainer(contentsOf: url)
            package = try EPUBPackage(container: container)
        } catch {
            throw EbookExtractor.Failure.unreadable
        }
        guard !EPUBProtection.isProtected(container) else { throw EbookExtractor.Failure.drmProtected }

        let navigation = EPUBNavigation.load(from: container, package: package)
        var chapters: [HTMLNode] = []
        for item in package.spine where chapterTypes.contains(item.mediaType) {
            guard let data = try? container.data(at: item.path), let body = await body(of: data) else { continue }
            chapters.append(HTMLNode(
                tag: "section", attributes: ["data-mr-chapter": navigation.title(forChapterAt: item.path) ?? ""],
                children: body.children.map { resolvingImages(in: $0, chapterPath: item.path) }))
        }

        let title = package.title ?? url.deletingPathExtension().lastPathComponent
        let built = HTMLStructureBuilder.build(
            from: HTMLNode(tag: "body", children: chapters), title: title, imagePrefix: "book", dropsRepeatedTitle: false
        ) { try? container.data(at: $0) }
        guard !built.blocks.isEmpty else { throw EbookExtractor.Failure.noText }

        let language = package.language
        let isRightToLeft = package.pageProgression == "rtl"
            || language?.split(separator: "-").first.map { MetadataResolver.rightToLeftLanguages.contains($0.lowercased()) } == true
        let metadata = ArticleMetadata(
            byline: package.authors.isEmpty ? nil : package.authors.joined(separator: ", "), siteName: package.publisher,
            publishedDate: EbookDate.parse(package.date), language: language, isRightToLeft: isRightToLeft,
            excerpt: package.summary)
        return EbookExtractor.Result(
            document: ReaderDocument(title: title, blocks: built.blocks, metadata: metadata), images: built.images, format: .epub)
    }

    /// A chapter's body: read as XML when it is, otherwise repaired by the browser's parser as a page would be.
    @MainActor
    private static func body(of data: Data) async -> HTMLNode? {
        if let document = try? XHTMLParser.parse(data) { return document.body }
        return try? await WebPageExtractor.serializeBody(html: HTMLSource.decode(data), baseURL: URL(fileURLWithPath: "/")).body
    }

    /// Picture addresses written relative to a chapter become paths from the book's root, which is how they are read.
    private static func resolvingImages(in node: HTMLNode, chapterPath: String) -> HTMLNode {
        var node = node
        if node.tag == "img", let source = node.attributes["src"], let path = EPUBPath.resolve(source, relativeTo: chapterPath) {
            node.attributes["src"] = path
        }
        node.children = node.children.map { resolvingImages(in: $0, chapterPath: chapterPath) }
        return node
    }
}
