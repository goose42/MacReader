import Foundation

/// Old-format Kindle books have no heading elements: a heading is a short paragraph set in a larger `<font size>`.
/// This turns those into real headings, and the elements `MOBI6Markup` marked from the contents page.
enum MOBI6Headings {
    /// Text longer than this is a paragraph that happens to be set large, not a heading.
    private static let longestHeading = 160
    private static let blocks: Set<String> = [
        "p", "div", "table", "ul", "ol", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6", "center", "hr",
    ]

    static func promote(_ node: HTMLNode) -> HTMLNode {
        var node = node
        node.children = node.children.map(promote)
        guard node.tag == "p" || node.tag == "div", !node.children.contains(where: containsBlock) else { return node }

        let marked = node.attributes[MOBI6Markup.headingAttribute] != nil
        let level = level(of: node)
        guard marked || level != nil else { return node }
        return HTMLNode(tag: "h\(level ?? 2)", children: node.children)
    }

    private static func containsBlock(_ node: HTMLNode) -> Bool {
        blocks.contains(node.tag) || node.children.contains(where: containsBlock)
    }

    /// Size 7 is the first level, 6 the second and 5 the third; nil unless all of the text is set at 5 or larger.
    private static func level(of block: HTMLNode) -> Int? {
        var smallest = Int.max
        var length = 0
        func visit(_ node: HTMLNode, size: Int) {
            if node.isText {
                let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                smallest = min(smallest, size)
                length += text.count
                return
            }
            let size = node.tag == "font" ? fontSize(node.attributes["size"], inheriting: size) : size
            for child in node.children { visit(child, size: size) }
        }
        visit(block, size: 3)
        guard length > 0, length <= longestHeading, smallest >= 5 else { return nil }
        return smallest >= 7 ? 1 : (smallest == 6 ? 2 : 3)
    }

    /// `<font size>` is 1 to 7 with 3 as normal, or relative to normal as `+2` or `-1`.
    private static func fontSize(_ value: String?, inheriting inherited: Int) -> Int {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return inherited }
        if value.hasPrefix("+"), let step = Int(value.dropFirst()) { return 3 + step }
        if value.hasPrefix("-"), let step = Int(value.dropFirst()) { return 3 - step }
        return Int(value) ?? inherited
    }
}
