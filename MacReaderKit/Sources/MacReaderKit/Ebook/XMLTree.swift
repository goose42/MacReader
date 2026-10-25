import Foundation

/// An element of a parsed XML document, with namespace prefixes removed from names so a reader can ask for `title`
/// and get `dc:title`. Case is kept, because OPF and NCX use camelCase names.
struct XMLTreeNode: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case text(String)
        case element(XMLTreeNode)
    }

    var name: String
    /// Attribute names without their prefixes (`opf:role` is `role`); namespace declarations are left out.
    var attributes: [String: String]
    var content: [Content] = []

    var children: [XMLTreeNode] {
        content.compactMap { if case .element(let node) = $0 { node } else { nil } }
    }

    func child(_ name: String) -> XMLTreeNode? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [XMLTreeNode] {
        children.filter { $0.name == name }
    }

    /// Every element beneath this one, in document order, that has the given name.
    func descendants(named name: String) -> [XMLTreeNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(named: name) }
    }

    /// All the text beneath this element, in order and unspaced.
    var textContent: String {
        content.map { item in
            switch item {
            case .text(let text): text
            case .element(let node): node.textContent
            }
        }.joined()
    }

    var trimmedText: String {
        textContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum XMLTree {
    enum Failure: Error, Equatable { case malformed(String) }

    static func parse(_ data: Data) throws -> XMLTreeNode {
        let builder = Builder()
        let parser = XMLParser(data: try XHTMLParser.resolveEntities(in: data))
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw Failure.malformed(parser.parserError?.localizedDescription ?? "not a document")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        private var stack: [XMLTreeNode] = []
        private(set) var root: XMLTreeNode?

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
            attributes attributeDict: [String: String]
        ) {
            var attributes: [String: String] = [:]
            for (key, value) in attributeDict where key != "xmlns" && !key.hasPrefix("xmlns:") {
                attributes[Self.localName(key)] = value
            }
            stack.append(XMLTreeNode(name: Self.localName(elementName), attributes: attributes))
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
        ) {
            guard let node = stack.popLast() else { return }
            if stack.isEmpty { root = node } else { stack[stack.count - 1].content.append(.element(node)) }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            append(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            append(String(decoding: CDATABlock, as: UTF8.self))
        }

        private func append(_ text: String) {
            guard !stack.isEmpty else { return }
            let last = stack.count - 1
            if case .text(let previous)? = stack[last].content.last {
                stack[last].content[stack[last].content.count - 1] = .text(previous + text)
            } else {
                stack[last].content.append(.text(text))
            }
        }

        private static func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }
}
