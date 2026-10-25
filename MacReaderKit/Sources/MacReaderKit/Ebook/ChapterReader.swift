import Foundation

/// Reads one file of a book's markup into the shared node tree.
enum ChapterReader {
    /// The body of a chapter: parsed as XML when it is well-formed, otherwise repaired by the browser's parser, as a
    /// web page would be. nil if neither can read it.
    @MainActor
    static func body(of data: Data) async -> HTMLNode? {
        if let document = try? XHTMLParser.parse(data) { return document.body }
        return try? await WebPageExtractor.serializeBody(html: HTMLSource.decode(data), baseURL: URL(fileURLWithPath: "/")).body
    }

    /// `node` with every picture's source rewritten by `address`, which returns nil to leave one as it is.
    static func resolvingPictures(in node: HTMLNode, using address: (String) -> String?) -> HTMLNode {
        var node = node
        if node.tag == "img", let source = node.attributes["src"], let resolved = address(source) {
            node.attributes["src"] = resolved
        }
        node.children = node.children.map { resolvingPictures(in: $0, using: address) }
        return node
    }
}
