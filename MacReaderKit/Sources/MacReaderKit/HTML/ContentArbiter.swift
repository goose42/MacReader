import Foundation

enum ContentSource: Equatable, Sendable {
    case readability, semantic, density, jsonLD, baseline
}

struct ContentChoice: Equatable, Sendable {
    var content: HTMLNode
    var source: ContentSource
}

/// Decides which extraction of the page to trust. No single method wins everywhere, so Readability's result is
/// cross-checked against independent ones and replaced only when another is clearly more complete: at least twice as
/// long and no more full of links.
enum ContentArbiter {
    private static let minimumArticleCharacters = 250
    private static let minimumFallbackCharacters = 100
    private static let linkDensityTolerance = 0.1
    private static let containmentThreshold = 0.8

    static func choose(_ payload: ExtractionPayload) -> ContentChoice? {
        let semantic = payload.body.flatMap(semanticCandidate)
        let density = payload.body.flatMap(DensityExtractor.bestNode)
        let jsonLD = articleBodyNode(from: payload.metadata.jsonLD, paragraphs: payload.paragraphs)

        guard let readability = payload.readability?.content, readability.textLength > 0 else {
            if let semantic { return ContentChoice(content: semantic, source: .semantic) }
            if let density { return ContentChoice(content: density, source: .density) }
            if let jsonLD { return ContentChoice(content: jsonLD, source: .jsonLD) }
            return payload.body.flatMap(baselineNode).map { ContentChoice(content: $0, source: .baseline) }
        }

        var best = ContentChoice(content: readability, source: .readability)
        let alternatives = [(semantic, ContentSource.semantic), (density, .density)].compactMap { node, source in
            node.map { ContentChoice(content: $0, source: source) }
        }
        if readability.textLength < minimumArticleCharacters {
            if let alternative = alternatives.first(where: { $0.content.textLength >= minimumArticleCharacters }) { best = alternative }
        } else {
            // Only a fuller version of the same article replaces it: longer, no more full of links, and containing what
            // Readability found, so a bigger block of sidebar text can't win on size alone.
            for alternative in alternatives where alternative.content.textLength > best.content.textLength * 2
                && alternative.content.linkDensity <= readability.linkDensity + linkDensityTolerance
                && coverage(of: readability, in: alternative.content) >= containmentThreshold {
                best = alternative
            }
        }
        if let jsonLD, prefersStructuredBody(jsonLD, over: best.content) { best = ContentChoice(content: jsonLD, source: .jsonLD) }
        return best
    }

    /// The page's declared article text wins when it is much longer, or when the chosen content lacks most of its
    /// words, as with a story a stylesheet collapses behind "Read more" while the page's other text stays visible.
    private static func prefersStructuredBody(_ declared: HTMLNode, over chosen: HTMLNode) -> Bool {
        if declared.textLength > chosen.textLength * 2 { return true }
        guard declared.textLength >= 300 else { return false }
        let chosenWords = Set(words(in: chosen.textContent))
        let declaredWords = words(in: declared.textContent)
        let found = declaredWords.filter(chosenWords.contains).count
        return Double(found) / Double(max(declaredWords.count, 1)) < 0.7
    }

    /// The share of `reference`'s distinct words that also appear in `content`.
    private static func coverage(of reference: HTMLNode, in content: HTMLNode) -> Double {
        let referenceWords = Set(words(in: reference.textContent))
        let contentWords = Set(words(in: content.textContent))
        return Double(referenceWords.filter(contentWords.contains).count) / Double(max(referenceWords.count, 1))
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// An element the page itself says holds the article: schema.org's `articleBody`, or its one `article` or `main`.
    private static func semanticCandidate(in body: HTMLNode) -> HTMLNode? {
        let marked = body.first { $0.attributes["itemprop"]?.lowercased().contains("articlebody") == true }
        let articles = body.all { $0.tag == "article" }
        let mains = body.all { $0.tag == "main" }
        let node = marked ?? (articles.count == 1 ? articles[0] : nil) ?? (mains.count == 1 ? mains[0] : nil)
        return node.flatMap { $0.textLength >= minimumArticleCharacters ? $0 : nil }
    }

    /// The `articleBody` of a schema.org article, as paragraphs.
    private static func articleBodyNode(from blocks: [String], paragraphs pageParagraphs: [String]) -> HTMLNode? {
        func find(_ value: Any) -> String? {
            if let array = value as? [Any] { return array.lazy.compactMap(find).first }
            guard let object = value as? [String: Any] else { return nil }
            if let body = object["articleBody"] as? String { return body }
            return object.values.lazy.compactMap(find).first
        }
        for block in blocks {
            guard let json = try? JSONSerialization.jsonObject(with: Data(block.utf8), options: [.fragmentsAllowed]), let body = find(json) else { continue }
            let text = HTMLEntities.decode(body)
            let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // Many pages run the paragraphs together; the page's own paragraphs show where they were.
            let paragraphs = lines.count > 1 ? lines : restoreParagraphs(of: lines.first ?? "", using: pageParagraphs)
            let node = HTMLNode(tag: "div", children: paragraphs.map { HTMLNode(tag: "p", children: [.text($0)]) })
            if node.textLength >= minimumFallbackCharacters { return node }
        }
        return nil
    }

    /// Splits text whose paragraph breaks were lost at the paragraphs of the page that appear in it, in order.
    private static func restoreParagraphs(of text: String, using pageParagraphs: [String]) -> [String] {
        func collapsed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        var rest = collapsed(text)
        var result: [String] = []
        for paragraph in pageParagraphs.map({ collapsed(HTMLEntities.decode($0)) }) where paragraph.count >= 25 {
            guard let range = rest.range(of: paragraph) else { continue }
            let before = String(rest[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { result.append(before) }
            result.append(paragraph)
            rest = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// Every real paragraph on the page, for when nothing better can be found.
    private static func baselineNode(in body: HTMLNode) -> HTMLNode? {
        let paragraphs = body.all { $0.tag == "p" && $0.textLength >= 25 }
        let node = HTMLNode(tag: "div", children: paragraphs)
        return node.textLength >= minimumFallbackCharacters ? node : nil
    }
}
