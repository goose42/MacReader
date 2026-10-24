import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns the DOM Readability chose into reader blocks: headings, paragraphs, list items, quotes, code, callouts,
/// tables, images and footnotes, in reading order.
struct HTMLStructureBuilder {
    struct Result {
        var blocks: [ReaderDocument.Block]
        /// Images the blocks refer to, keyed by file name.
        var images: [String: Data]
    }

    /// `loadImage` is handed an image's address exactly as the page wrote it and returns its bytes, or nil when it
    /// can't be had offline.
    static func build(from root: HTMLNode, title: String, loadImage: @escaping (String) -> Data?) -> Result {
        let walker = Walker(loadImage: loadImage)
        walker.walkChildren(of: root)
        var blocks = dropRepeatedTitle(walker.blocks, title: title)
        blocks = closeUpHeadingLevels(blocks)
        return Result(blocks: HeadingNumbering.apply(to: blocks), images: walker.images)
    }

    /// The page's own heading that repeats its title is already shown as the document title.
    private static func dropRepeatedTitle(_ blocks: [ReaderDocument.Block], title: String) -> [ReaderDocument.Block] {
        for (index, block) in blocks.enumerated() {
            guard case .heading = block.kind else { return blocks }
            if TextSimilarity.score(title, block.text) > 0.75 {
                var kept = blocks
                kept.remove(at: index)
                return kept
            }
        }
        return blocks
    }

    /// Pages skip levels (an h2 followed by h4s); the distinct levels in use become 1, 2, 3 in order.
    private static func closeUpHeadingLevels(_ blocks: [ReaderDocument.Block]) -> [ReaderDocument.Block] {
        let levels = Set(blocks.compactMap { block -> Int? in
            if case .heading(let level) = block.kind { return level }
            return nil
        }).sorted()
        return blocks.map { block in
            guard case .heading(let level) = block.kind, let rank = levels.firstIndex(of: level) else { return block }
            return .init(id: block.id, kind: .heading(level: rank + 1), text: block.text, numbering: block.numbering)
        }
    }
}

private final class Walker {
    private(set) var blocks: [ReaderDocument.Block] = []
    private(set) var images: [String: Data] = [:]
    private var imageCount = 0
    private let loadImage: (String) -> Data?

    init(loadImage: @escaping (String) -> Data?) {
        self.loadImage = loadImage
    }

    // MARK: Vocabulary

    private static let skipped: Set<String> = [
        "script", "style", "noscript", "template", "nav", "form", "iframe", "button", "input", "select", "textarea", "svg",
        "canvas", "video", "audio", "object", "embed", "dialog", "footer", "link", "meta", "head",
    ]
    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "main", "header", "aside", "figure", "figcaption", "blockquote", "pre", "ul", "ol",
        "dl", "dt", "dd", "li", "table", "thead", "tbody", "tfoot", "tr", "td", "th", "caption", "h1", "h2", "h3", "h4", "h5",
        "h6", "hr", "details", "summary", "fieldset", "address", "center", "body", "html", "picture", "img",
    ]
    private static let calloutClasses: Set<String> = ["callout", "admonition", "notice", "markdown-alert", "alert"]
    private static let calloutRoles: Set<String> = ["note", "doc-tip", "doc-notice"]
    private static let noteContainerClasses: Set<String> = [
        "references", "footnotes", "footnote-list", "footnotes-list", "wp-block-footnotes", "endnotes",
    ]
    private static let noteReferenceClasses: Set<String> = [
        "reference", "footnote-ref", "footnote-anchor", "footnote-reference", "fn",
    ]
    private static let backlinkClasses: Set<String> = [
        "backlink", "backref", "footnote-backref", "mw-cite-backlink", "reversefootnote",
    ]
    private static let backlinkGlyphs: Set<String> = ["↩", "↩︎", "^", "↑", "⏎", "↵"]
    private static let permalinkGlyphs: Set<String> = ["#", "¶", "§", "🔗"]
    private static let bullets = ["•", "◦", "▪"]
    private static let smallestImageSide = 32

    // MARK: Walking

    private func emit(_ kind: ReaderDocument.Block.Kind, _ text: String) {
        blocks.append(.init(id: blocks.count, kind: kind, text: text))
    }

    /// Loose inline content becomes paragraphs; block children are handled where they stand.
    func walkChildren(of node: HTMLNode) {
        var run: [HTMLNode] = []
        func flush() {
            for text in paragraphs(from: run) { emit(.paragraph, text) }
            run = []
        }
        for child in node.children {
            if child.isText || !(Self.blockTags.contains(child.tag) || Self.skipped.contains(child.tag)) {
                run.append(child)
            } else {
                flush()
                walkBlock(child)
            }
        }
        flush()
    }

    private func walkBlock(_ node: HTMLNode) {
        let tag = node.tag
        if Self.skipped.contains(tag) { return }
        if isNoteContainer(node) { return emitNotes(in: node) }
        if isCallout(node) { return emitCallout(node) }
        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let text = flatText(node.children)
            if !text.isEmpty { emit(.heading(level: Int(tag.dropFirst()) ?? 2), text) }
        case "ul", "ol": emitList(node, depth: 0)
        case "pre": emitCode(rawText(of: node))
        case "blockquote": emitQuote(node)
        case "table": emitTable(node)
        case "img", "picture": emitImage(node)
        case "figcaption":
            let text = flatText(node.children)
            if !text.isEmpty { emit(.caption, text) }
        case "hr": break
        default:
            if node.attributes["data-mr-mono"] != nil, node.attributes["data-mr-pre"] != nil {
                emitCode(rawText(of: node))
            } else {
                walkChildren(of: node)
            }
        }
    }

    // MARK: Text

    private func paragraphs(from nodes: [HTMLNode]) -> [String] {
        var raw = ""
        collectInline(nodes, into: &raw)
        return raw.split(separator: /\u{1}(?:\s*\u{1})+/).compactMap { part in
            let text = collapse(String(part).replacingOccurrences(of: "\u{1}", with: " "))
            return text.isEmpty ? nil : text
        }
    }

    /// All the text of `nodes` as one line, block boundaries and line breaks becoming spaces.
    private func flatText(_ nodes: [HTMLNode]) -> String {
        var raw = ""
        collectInline(nodes, into: &raw)
        return collapse(raw.replacingOccurrences(of: "\u{1}", with: " "))
    }

    private func collapse(_ text: String) -> String {
        text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Appends the visible text of `nodes`; a line break is written as U+0001 so runs of them can split paragraphs.
    private func collectInline(_ nodes: [HTMLNode], into out: inout String) {
        for node in nodes {
            if node.isText { out += node.text; continue }
            switch node.tag {
            case "br": out += "\u{1}"; continue
            case "img", "picture": continue
            case "math": out += mathText(node); continue
            default: break
            }
            if Self.skipped.contains(node.tag) || isNoteReference(node) || isBacklink(node) || isPermalink(node)
                || classes(of: node).contains("katex-html") { continue }
            let isBlock = Self.blockTags.contains(node.tag)
            if isBlock { out += " " }
            collectInline(node.children, into: &out)
            if isBlock { out += " " }
        }
    }

    /// Text with its own line breaks and indentation, for preformatted blocks.
    private func rawText(of node: HTMLNode) -> String {
        var out = ""
        func collect(_ node: HTMLNode) {
            if node.isText { out += node.text; return }
            if node.tag == "br" { out += "\n"; return }
            if Self.skipped.contains(node.tag) { return }
            node.children.forEach(collect)
            if Self.blockTags.contains(node.tag), !out.hasSuffix("\n") { out += "\n" }
        }
        node.children.forEach(collect)
        return out
    }

    private func mathText(_ node: HTMLNode) -> String {
        func annotation(_ node: HTMLNode) -> String? {
            if node.tag == "annotation", node.attributes["encoding"]?.contains("tex") == true { return node.textContent }
            return node.children.lazy.compactMap(annotation).first
        }
        return annotation(node) ?? node.attributes["alttext"] ?? node.textContent
    }

    private func emitCode(_ text: String) {
        var lines = text.components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        let code = lines.joined(separator: "\n")
        if !code.isEmpty { emit(.code, code) }
    }

    // MARK: Classification

    private func classes(of node: HTMLNode) -> Set<String> {
        Set((node.attributes["class"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    }

    private func isNoteReference(_ node: HTMLNode) -> Bool {
        guard node.tag == "sup" || node.tag == "a" || node.tag == "span" else { return false }
        if node.attributes["role"] == "doc-noteref" || node.attributes["epub:type"]?.contains("noteref") == true { return true }
        if node.attributes["data-fn"] != nil || !classes(of: node).isDisjoint(with: Self.noteReferenceClasses) { return true }
        return false
    }

    private func isBacklink(_ node: HTMLNode) -> Bool {
        guard node.tag == "a" || node.tag == "span" else { return false }
        if node.attributes["role"] == "doc-backlink" || !classes(of: node).isDisjoint(with: Self.backlinkClasses) { return true }
        return node.tag == "a" && Self.backlinkGlyphs.contains(node.textContent.trimmingCharacters(in: .whitespaces))
    }

    private func isPermalink(_ node: HTMLNode) -> Bool {
        node.tag == "a" && Self.permalinkGlyphs.contains(node.textContent.trimmingCharacters(in: .whitespaces))
    }

    private func isCallout(_ node: HTMLNode) -> Bool {
        node.tag == "aside" || node.tag == "details"
            || node.attributes["role"].map(Self.calloutRoles.contains) == true
            || !classes(of: node).isDisjoint(with: Self.calloutClasses)
    }

    private func isNoteContainer(_ node: HTMLNode) -> Bool {
        if let role = node.attributes["role"], role == "doc-endnotes" || role == "doc-footnotes" { return true }
        guard ["ol", "ul", "div", "section", "aside"].contains(node.tag) else { return false }
        let tokens = classes(of: node)
        return !tokens.isDisjoint(with: Self.noteContainerClasses) || (node.tag == "div" && tokens.contains("footnote"))
    }

    // MARK: Blocks

    private func emitCallout(_ node: HTMLNode) {
        let start = blocks.count
        walkChildren(of: node)
        let inner = blocks[start...]
        let text = inner.filter { block in
            switch block.kind {
            case .paragraph, .heading, .listItem, .quote, .caption: true
            default: false
            }
        }.map(\.text).joined(separator: " ")
        for block in inner { if case .image(let name, _) = block.kind { images[name] = nil } }
        blocks.removeSubrange(start...)
        if !text.isEmpty { emit(.callout, text) }
    }

    private func emitQuote(_ node: HTMLNode) {
        let start = blocks.count
        walkChildren(of: node)
        for index in start..<blocks.count where blocks[index].kind == .paragraph {
            blocks[index] = .init(id: blocks[index].id, kind: .quote, text: blocks[index].text)
        }
    }

    private func emitList(_ node: HTMLNode, depth: Int) {
        let ordered = node.tag == "ol"
        var number = Int(node.attributes["start"] ?? "") ?? 1
        for child in node.children {
            if child.tag == "ul" || child.tag == "ol" { emitList(child, depth: depth + 1); continue }
            guard child.tag == "li" else { continue }
            let marker = ordered ? "\(number)." : Self.bullets[min(depth, Self.bullets.count - 1)]
            number += 1
            let content = child.children.filter { $0.tag != "ul" && $0.tag != "ol" }
            let text = flatText(content)
            if !text.isEmpty { emit(.listItem(marker: marker, depth: depth), text) }
            for nested in child.children where nested.tag == "ul" || nested.tag == "ol" { emitList(nested, depth: depth + 1) }
        }
    }

    // MARK: Footnotes

    private func emitNotes(in container: HTMLNode) {
        var items: [HTMLNode] = []
        func find(in node: HTMLNode) {
            for child in node.children {
                if child.tag == "li" || child.attributes["role"] == "doc-footnote" || (child.tag == "div" && classes(of: child).contains("footnote")) {
                    items.append(child)
                } else {
                    find(in: child)
                }
            }
        }
        if container.tag == "div", classes(of: container).contains("footnote") { items = [container] } else { find(in: container) }

        for (index, item) in items.enumerated() {
            let number = firstDescendant(of: item) { classes(of: $0).contains("footnote-number") }
            let marker = number.map { flatText([$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".[]() ")) } ?? "\(index + 1)"
            let source = firstDescendant(of: item) { classes(of: $0).contains("footnote-content") } ?? item
            let text = flatText(source.children)
            if !text.isEmpty { emit(.footnote(marker: marker.isEmpty ? "\(index + 1)" : marker), text) }
        }
    }

    private func firstDescendant(of node: HTMLNode, where matches: (HTMLNode) -> Bool) -> HTMLNode? {
        for child in node.children {
            if matches(child) { return child }
            if let found = firstDescendant(of: child, where: matches) { return found }
        }
        return nil
    }

    // MARK: Tables

    private func emitTable(_ table: HTMLNode) {
        var rows: [HTMLNode] = []
        func gather(_ node: HTMLNode) {
            for child in node.children {
                if child.tag == "tr" { rows.append(child) } else if ["thead", "tbody", "tfoot"].contains(child.tag) { gather(child) }
            }
        }
        gather(table)
        let cellRows = rows.map { $0.children.filter { $0.tag == "td" || $0.tag == "th" } }

        guard isDataTable(table, cellRows: cellRows) else {
            for cell in cellRows.joined() { walkChildren(of: cell) }
            return
        }

        var grid: [[String]] = []
        var carried: [Int: Int] = [:]
        for cells in cellRows {
            var row: [String] = []
            func fillCarried() {
                while carried[row.count, default: 0] > 0 {
                    carried[row.count]! -= 1
                    row.append("")
                }
            }
            for cell in cells {
                fillCarried()
                let start = row.count
                let colspan = max(1, min(Int(cell.attributes["colspan"] ?? "") ?? 1, 100))
                let rowspan = max(1, min(Int(cell.attributes["rowspan"] ?? "") ?? 1, 100))
                row.append(flatText(cell.children))
                row.append(contentsOf: Array(repeating: "", count: colspan - 1))
                if rowspan > 1 { for column in start..<start + colspan { carried[column] = rowspan - 1 } }
            }
            fillCarried()
            grid.append(row)
        }
        grid.removeAll { $0.allSatisfy(\.isEmpty) }
        guard !grid.isEmpty else { return }
        let width = grid.map(\.count).max() ?? 0
        grid = grid.map { $0 + Array(repeating: "", count: width - $0.count) }

        let hasHeader = cellRows.first.map { !$0.isEmpty && $0.allSatisfy { $0.tag == "th" } } ?? false
        blocks.append(.table(id: blocks.count, rows: grid, hasHeader: hasHeader))
        if let caption = table.children.first(where: { $0.tag == "caption" }) {
            let text = flatText(caption.children)
            if !text.isEmpty { emit(.caption, text) }
        }
    }

    /// Readability's test for whether a table holds data rather than laying out the page.
    private func isDataTable(_ table: HTMLNode, cellRows: [[HTMLNode]]) -> Bool {
        if let role = table.attributes["role"], role == "presentation" || role == "none" { return false }
        if table.attributes["datatable"] == "0" { return false }
        if table.attributes["summary"]?.isEmpty == false { return true }
        if table.children.contains(where: { $0.tag == "caption" }) { return true }
        if firstDescendant(of: table, where: { ["col", "colgroup", "tfoot", "thead", "th"].contains($0.tag) }) != nil { return true }
        if firstDescendant(of: table, where: { $0.tag == "table" }) != nil { return false }
        let rowCount = cellRows.count
        let columnCount = cellRows.map { cells in cells.reduce(0) { $0 + max(1, Int($1.attributes["colspan"] ?? "") ?? 1) } }.max() ?? 0
        if rowCount <= 1 || columnCount <= 1 { return false }
        if rowCount >= 10 || columnCount > 4 { return true }
        return rowCount * columnCount > 10
    }

    // MARK: Images

    private func emitImage(_ node: HTMLNode) {
        var candidates: [String] = []
        let img = node.tag == "picture" ? node.children.first(where: { $0.tag == "img" }) : node
        if node.tag == "picture" {
            for source in node.children where source.tag == "source" {
                if let best = largest(in: source.attributes["srcset"]) { candidates.append(best) }
            }
        }
        if let img {
            for attribute in ["srcset", "data-srcset"] {
                if let best = largest(in: img.attributes[attribute]) { candidates.append(best) }
            }
            candidates += ["data-src", "src"].compactMap { img.attributes[$0] }.filter { !$0.isEmpty }
        }

        for candidate in candidates {
            guard let data = loadImage(candidate), let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  min(width, height) >= Self.smallestImageSide
            else { continue }
            let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
            imageCount += 1
            let name = "web-\(imageCount).\(type?.preferredFilenameExtension ?? "img")"
            images[name] = data
            blocks.append(.init(id: blocks.count, kind: .image(name: name, aspectRatio: Double(width) / Double(height)), text: ""))
            return
        }
    }

    /// The address with the largest width or pixel density in a `srcset`, which an offline reader prefers.
    private func largest(in srcset: String?) -> String? {
        guard let srcset else { return nil }
        let tokens = srcset.split(whereSeparator: \.isWhitespace).map(String.init)
        var best: (url: String, weight: Double)?
        var index = 0
        while index < tokens.count {
            let url = tokens[index].trimmingCharacters(in: CharacterSet(charactersIn: ","))
            var weight = 1000.0
            if index + 1 < tokens.count,
               let match = tokens[index + 1].trimmingCharacters(in: CharacterSet(charactersIn: ",")).wholeMatch(of: /(\d+(?:\.\d+)?)([wx])/),
               let value = Double(match.1) {
                weight = match.2 == "w" ? value : value * 1000
                index += 1
            }
            if !url.isEmpty, weight > (best?.weight ?? 0) { best = (url, weight) }
            index += 1
        }
        return best?.url
    }
}
