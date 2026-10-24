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

    static func choose(_ payload: ExtractionPayload) -> ContentChoice? {
        let semantic = payload.body.flatMap(semanticCandidate)
        let density = payload.body.flatMap(DensityExtractor.bestNode)
        let jsonLD = articleBodyNode(from: payload.metadata.jsonLD)

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
            for alternative in alternatives where alternative.content.textLength > best.content.textLength * 2
                && alternative.content.linkDensity <= readability.linkDensity + linkDensityTolerance {
                best = alternative
            }
        }
        if let jsonLD, jsonLD.textLength > best.content.textLength * 2 { best = ContentChoice(content: jsonLD, source: .jsonLD) }
        return best
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
    private static func articleBodyNode(from blocks: [String]) -> HTMLNode? {
        func find(_ value: Any) -> String? {
            if let array = value as? [Any] { return array.lazy.compactMap(find).first }
            guard let object = value as? [String: Any] else { return nil }
            if let body = object["articleBody"] as? String { return body }
            return object.values.lazy.compactMap(find).first
        }
        for block in blocks {
            guard let json = try? JSONSerialization.jsonObject(with: Data(block.utf8), options: [.fragmentsAllowed]), let body = find(json) else { continue }
            let paragraphs = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let node = HTMLNode(tag: "div", children: paragraphs.map { HTMLNode(tag: "p", children: [.text($0)]) })
            if node.textLength >= minimumFallbackCharacters { return node }
        }
        return nil
    }

    /// Every real paragraph on the page, for when nothing better can be found.
    private static func baselineNode(in body: HTMLNode) -> HTMLNode? {
        let paragraphs = body.all { $0.tag == "p" && $0.textLength >= 25 }
        let node = HTMLNode(tag: "div", children: paragraphs)
        return node.textLength >= minimumFallbackCharacters ? node : nil
    }
}
