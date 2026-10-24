@testable import MacReaderKit

/// A terse way to write DOM fixtures: `el("p", [:], "text", el("a", ["href": "/"], "link"))`.
extension HTMLNode: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
}

func el(_ tag: String, _ attributes: [String: String] = [:], _ children: HTMLNode...) -> HTMLNode {
    HTMLNode(tag: tag, attributes: attributes, children: children)
}
