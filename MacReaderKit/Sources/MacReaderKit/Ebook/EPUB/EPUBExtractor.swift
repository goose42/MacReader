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
            guard let data = try? container.data(at: item.path), let body = await ChapterReader.body(of: data) else { continue }
            chapters.append(HTMLNode(
                tag: "section", attributes: ["data-mr-chapter": navigation.title(forChapterAt: item.path) ?? ""],
                children: body.children.map { node in
                    // Picture addresses written relative to a chapter become paths from the book's root.
                    ChapterReader.resolvingPictures(in: node) { EPUBPath.resolve($0, relativeTo: item.path) }
                }))
        }

        let title = package.title ?? url.deletingPathExtension().lastPathComponent
        let built = HTMLStructureBuilder.build(
            from: HTMLNode(tag: "body", children: chapters), title: title, imagePrefix: "book", dropsRepeatedTitle: false
        ) { try? container.data(at: $0) }
        guard !built.blocks.isEmpty else { throw EbookExtractor.Failure.noText }

        let language = package.language
        let isRightToLeft = package.pageProgression == "rtl" || EbookText.isRightToLeft(language: language)
        let metadata = ArticleMetadata(
            byline: package.authors.isEmpty ? nil : package.authors.joined(separator: ", "), siteName: package.publisher,
            publishedDate: EbookDate.parse(package.date), language: language, isRightToLeft: isRightToLeft,
            excerpt: package.summary)
        return EbookExtractor.Result(
            document: ReaderDocument(title: title, blocks: built.blocks, metadata: metadata), images: built.images, format: .epub)
    }
}
