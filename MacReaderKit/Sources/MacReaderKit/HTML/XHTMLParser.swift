import Foundation

/// Reads a well-formed XHTML document, such as an EPUB chapter, into the same `HTMLNode` tree the web pipeline builds
/// from a rendered page. Nothing here needs a web view, so books made of valid XHTML never leave Swift.
enum XHTMLParser {
    enum Failure: Error, Equatable { case malformed(String) }

    struct Document: Equatable {
        /// The `<body>`, or a stand-in holding the top-level content when the file has none.
        var body: HTMLNode
        var title: String
        var language: String?
        var direction: String?
    }

    /// The attributes `serialize.js` reports; the builder reads nothing else.
    private static let kept: Set<String> = [
        "href", "src", "srcset", "alt", "title", "id", "class", "role", "colspan", "rowspan", "start", "type", "lang",
        "dir", "datetime", "width", "height", "aria-label", "epub:type", "itemprop", "data-fn", "data-src",
        "data-srcset", "alttext", "encoding",
    ]

    static func parse(_ data: Data) throws -> Document {
        let builder = TreeBuilder()
        let parser = XMLParser(data: try resolveEntities(in: data))
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), let top = builder.top else {
            throw Failure.malformed(parser.parserError?.localizedDescription ?? "not a document")
        }

        let html = top.first { $0.tag == "html" }
        let container = html?.children ?? top
        let body = container.first { $0.tag == "body" }
            ?? HTMLNode(tag: "body", children: container.filter { $0.tag != "head" })
        let title = container.first { $0.tag == "head" }?.first { $0.tag == "title" }?.textContent ?? ""
        return Document(
            body: body,
            title: title.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces),
            language: html?.attributes["lang"],
            direction: html?.attributes["dir"])
    }

    /// XML knows five entities; XHTML files use the HTML ones (`&nbsp;`) and rely on a DTD the parser never fetches.
    /// They are rewritten as numeric references, and the prolog's encoding is set to what the text now is.
    /// A name nobody can resolve is an error, because the XML parser would silently drop it along with its text.
    private static func resolveEntities(in data: Data) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        if text.contains("&") {
            let predefined: Set<String> = ["amp", "lt", "gt", "quot", "apos"]
            var unknown: String?
            text = text.replacing(/&([A-Za-z][A-Za-z0-9]*);/) { match in
                let reference = String(match.0)
                guard !predefined.contains(String(match.1)) else { return reference }
                let decoded = HTMLEntities.decode(reference)
                if decoded == reference { unknown = reference }
                return decoded == reference ? reference : decoded.unicodeScalars.map { "&#\($0.value);" }.joined()
            }
            if let unknown { throw Failure.malformed("unknown entity \(unknown)") }
        }
        if let prolog = text.prefixMatch(of: /\s*<\?xml[^>]*\?>/) {
            let fixed = String(prolog.0).replacing(/encoding\s*=\s*(["'])[^"']*\1/, with: #"encoding="utf-8""#)
            text.replaceSubrange(prolog.range, with: fixed)
        }
        return Data(text.utf8)
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        private struct Open {
            var tag: String
            var attributes: [String: String]
            var children: [HTMLNode] = []
        }

        private var stack = [Open(tag: "#root", attributes: [:])]
        private(set) var top: [HTMLNode]?

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
            attributes attributeDict: [String: String]
        ) {
            stack.append(Open(tag: Self.localName(elementName), attributes: Self.filter(attributeDict)))
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
        ) {
            guard stack.count > 1 else { return }
            let open = stack.removeLast()
            let node = HTMLNode(tag: open.tag, attributes: open.attributes, children: open.children)
            stack[stack.count - 1].children.append(Self.pictureFromSVG(node))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            append(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            append(String(decoding: CDATABlock, as: UTF8.self))
        }

        func parserDidEndDocument(_ parser: XMLParser) {
            if stack.count == 1 { top = stack[0].children }
        }

        private func append(_ text: String) {
            let index = stack.count - 1
            if let last = stack[index].children.last, last.isText {
                stack[index].children[stack[index].children.count - 1].text += text
            } else {
                stack[index].children.append(.text(text))
            }
        }

        private static func localName(_ name: String) -> String {
            (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
        }

        private static func filter(_ attributes: [String: String]) -> [String: String] {
            var result: [String: String] = [:]
            for (rawKey, value) in attributes {
                var key = rawKey.lowercased()
                if key == "xlink:href" { key = "href" }
                if key == "xml:lang" { if result["lang"] == nil, attributes["lang"] == nil { result["lang"] = value }; continue }
                if kept.contains(key) || key.hasPrefix("data-mr-") { result[key] = value }
            }
            return result
        }

        /// Covers are often an SVG wrapping one `<image>`; the builder skips SVG but reads pictures.
        private static func pictureFromSVG(_ node: HTMLNode) -> HTMLNode {
            guard node.tag == "svg",
                  let address = node.first(where: { $0.tag == "image" && $0.attributes["href"] != nil })?.attributes["href"]
            else { return node }
            return HTMLNode(tag: "img", attributes: ["src": address])
        }
    }
}
