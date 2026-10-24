import Foundation

/// Cleans the chosen content of what extraction lets through: link-only blocks, the "Related articles" and comments
/// that trail an article, copyright lines, repeated paragraphs and the byline and date the header already shows.
enum BoilerplateFilter {
    /// A terminating heading only counts this far into the text, so an early section called "Comments" survives.
    private static let tailStart = 0.6
    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "main", "header", "aside", "figure", "blockquote", "pre", "ul", "ol", "li", "table",
        "h1", "h2", "h3", "h4", "h5", "h6", "details", "mr-callout",
    ]
    private static let wrapperTags: Set<String> = ["div", "section", "article", "p", "ul", "ol", "li", "figure", "blockquote", "header", "span"]
    private static let mediaTags: Set<String> = ["img", "picture", "svg", "video", "table", "pre", "math"]

    nonisolated(unsafe) private static let terminating = /(?i)\s*(?:related\s+(?:articles?|posts?|stories|reading|links|content|topics)|you\s+(?:may|might|could)\s+also\s+(?:like|enjoy)|you\s+may\s+like|more\s+(?:from|stories|articles|on|in)\b.*|read\s+(?:next|more|also)|also\s+read|recommended(?:\s+for\s+you|\s+reading)?|share\s+(?:this|on|with)\b.*|leave\s+a\s+(?:comment|reply)|(?:\d+\s+)?(?:comments?|responses?|replies)|post\s+a\s+comment|about\s+the\s+author|subscribe(?:\s+to\b.*)?|sign\s+up\b.*|newsletter|advertisement|sponsored(?:\s+content)?|tags?|filed\s+under\b.*|trending(?:\s+now)?)\s*:?\s*/
    nonisolated(unsafe) private static let copyright = /(?i)\s*(?:©|\(c\)|copyright\b).*/
    nonisolated(unsafe) private static let metadataPrefix = /(?i)(?:written\s+by|posted\s+by|published|updated|posted|date|by)\s*:?\s*/

    static func filter(_ root: HTMLNode, byline: String?, publishedDate: Date?) -> HTMLNode {
        let state = State(total: root.textLength, byline: byline.map(simplified), dates: publishedDate.map(dateStrings) ?? [])
        var result = root
        result.children = root.children.compactMap { prune($0, state) }
        return result
    }

    private final class State {
        let total: Int
        let byline: String?
        let dates: [String]
        var consumed = 0
        var stopped = false
        var seenBody = false
        var paragraphs: Set<String> = []

        init(total: Int, byline: String?, dates: [String]) {
            self.total = total
            self.byline = byline
            self.dates = dates
        }
    }

    private static func prune(_ node: HTMLNode, _ state: State) -> HTMLNode? {
        if node.isText {
            state.consumed += node.textLength
            return node
        }
        if state.stopped { return nil }
        let length = node.textLength
        let hasMedia = node.first { mediaTags.contains($0.tag) } != nil

        func drop() -> HTMLNode? {
            state.consumed += length
            return nil
        }

        let leaf = isLeafBlock(node)
        if leaf, length <= 60, node.textContent.wholeMatch(of: terminating) != nil, Double(state.consumed) >= tailStart * Double(state.total) {
            state.stopped = true
            return nil
        }
        if !hasMedia, isLinkHeavy(node, length: length) { return drop() }
        if (node.tag == "p" || node.tag == "div"), leaf, length <= 150, node.textContent.wholeMatch(of: copyright) != nil { return drop() }
        if !state.seenBody, leaf, node.tag == "p" || node.tag == "div" {
            if length >= 100 { state.seenBody = true } else if isMetadataLine(node.textContent, state) { return drop() }
        }
        if node.tag == "p", length >= 100 {
            let key = node.textContent.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
            if !state.paragraphs.insert(key).inserted { return drop() }
        }

        var copy = node
        copy.children = node.children.compactMap { prune($0, state) }
        if wrapperTags.contains(node.tag), copy.textLength == 0, copy.first(where: { mediaTags.contains($0.tag) }) == nil { return nil }
        return copy
    }

    /// A block with no block inside it: a paragraph, heading, list item or div of running text.
    private static func isLeafBlock(_ node: HTMLNode) -> Bool {
        guard ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6"].contains(node.tag) else { return false }
        return !node.children.contains(where: containsBlock)
    }

    private static func containsBlock(_ node: HTMLNode) -> Bool {
        !node.isText && (blockTags.contains(node.tag) || node.children.contains(where: containsBlock))
    }

    private static func isLinkHeavy(_ node: HTMLNode, length: Int) -> Bool {
        guard length > 0 else { return false }
        let density = Double(node.linkTextLength) / Double(length)
        switch node.tag {
        case "ul", "ol": return node.children.filter { $0.tag == "li" }.count >= 3 && density > 0.6
        case "div", "section", "p", "aside": return density > 0.8 && length < 500
        default: return false
        }
    }

    private static func isMetadataLine(_ text: String, _ state: State) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var remainder = trimmed
        if let match = trimmed.prefixMatch(of: metadataPrefix) { remainder = String(trimmed[match.range.upperBound...]) }
        if let byline = state.byline, simplified(remainder) == byline { return true }
        return state.dates.contains { trimmed.contains($0) }
    }

    private static func simplified(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The date as pages commonly print it.
    private static func dateStrings(_ date: Date) -> [String] {
        ["MMMM d, yyyy", "d MMMM yyyy", "MMM d, yyyy", "d MMM yyyy", "yyyy-MM-dd", "MM/dd/yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
    }
}
