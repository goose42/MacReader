import Foundation

/// A node of the page's DOM as the extraction scripts report it. Text nodes have the tag `#text`.
struct HTMLNode: Codable, Equatable, Sendable {
    var tag: String
    var text: String
    var attributes: [String: String]
    var children: [HTMLNode]

    init(tag: String, text: String = "", attributes: [String: String] = [:], children: [HTMLNode] = []) {
        self.tag = tag
        self.text = text
        self.attributes = attributes
        self.children = children
    }

    private enum CodingKeys: String, CodingKey { case tag, text, attributes = "attrs", children }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decode(String.self, forKey: .tag)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        attributes = try container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        children = try container.decodeIfPresent([HTMLNode].self, forKey: .children) ?? []
    }

    static func text(_ text: String) -> HTMLNode { HTMLNode(tag: "#text", text: text) }

    var isText: Bool { tag == "#text" }

    subscript(attribute: String) -> String? { attributes[attribute] }

    /// All the text beneath this node, unspaced.
    var textContent: String {
        isText ? text : children.map(\.textContent).joined()
    }
}

/// What the page's own markup says about the article, before anything is chosen between.
struct RawMetadata: Codable, Equatable, Sendable {
    var title: String = ""
    /// Contents of every `<script type="application/ld+json">`.
    var jsonLD: [String] = []
    /// Each `<meta>` as lowercased `name`/`property`/`itemprop`/`http-equiv` and its content, in document order.
    var meta: [MetaTag] = []
    var canonicalURL: String?
    var headings: [String] = []
    var language: String?
    var direction: String?
    var baseURL: String?

    struct MetaTag: Codable, Equatable, Sendable {
        var key: String
        var content: String
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        jsonLD = try container.decodeIfPresent([String].self, forKey: .jsonLD) ?? []
        meta = try container.decodeIfPresent([MetaTag].self, forKey: .meta) ?? []
        canonicalURL = try container.decodeIfPresent(String.self, forKey: .canonicalURL)
        headings = try container.decodeIfPresent([String].self, forKey: .headings) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
    }
}

/// What Readability found on the page.
struct ReadabilityResult: Codable, Equatable, Sendable {
    var content: HTMLNode
    var title: String?
    var byline: String?
    var excerpt: String?
    var siteName: String?
    var publishedTime: String?
}

/// Everything the scripts report about one page; Swift decides what to keep.
struct ExtractionPayload: Codable, Equatable, Sendable {
    var readability: ReadabilityResult?
    var metadata: RawMetadata
    /// The whole page body after junk was pruned, for the alternatives Readability is checked against.
    var body: HTMLNode?

    init(readability: ReadabilityResult? = nil, metadata: RawMetadata = RawMetadata(), body: HTMLNode? = nil) {
        self.readability = readability
        self.metadata = metadata
        self.body = body
    }
}

extension HTMLNode {
    /// Characters of text beneath this node, with runs of whitespace counted as one space.
    var textLength: Int {
        textContent.split(whereSeparator: \.isWhitespace).joined(separator: " ").count
    }

    /// How much of that text sits inside links.
    var linkTextLength: Int {
        tag == "a" ? textLength : children.reduce(0) { $0 + $1.linkTextLength }
    }

    var linkDensity: Double {
        let length = textLength
        return length == 0 ? 0 : Double(linkTextLength) / Double(length)
    }

    /// The first node in this subtree, this one included, that satisfies `matches`.
    func first(where matches: (HTMLNode) -> Bool) -> HTMLNode? {
        if matches(self) { return self }
        for child in children { if let found = child.first(where: matches) { return found } }
        return nil
    }

    func all(where matches: (HTMLNode) -> Bool) -> [HTMLNode] {
        (matches(self) ? [self] : []) + children.flatMap { $0.all(where: matches) }
    }
}
