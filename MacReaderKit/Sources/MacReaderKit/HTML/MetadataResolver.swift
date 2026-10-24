import Foundation

/// Chooses a page's title, byline, date and the rest from what its markup offers, trusting structured data (JSON-LD,
/// then OpenGraph and meta tags) over what Readability guessed from the text.
enum MetadataResolver {
    struct Resolved: Equatable {
        var title: String?
        var byline: String?
        var siteName: String?
        var publishedDate: Date?
        var sourceURL: URL?
        var language: String?
        var isRightToLeft = false
        var excerpt: String?
    }

    private static let rightToLeftLanguages: Set<String> = ["ar", "he", "fa", "ur", "yi", "ps", "sd", "ug", "dv", "ckb"]
    private static let otherArticleTypes: Set<String> = ["BlogPosting", "LiveBlogPosting", "SocialMediaPosting", "Report", "DiscussionForumPosting", "APIReference"]

    static func resolve(_ raw: RawMetadata, readability: ReadabilityResult?, savedFromURL: URL?, now: Date = Date()) -> Resolved {
        let nodes = jsonLDNodes(raw.jsonLD)
        let article = nodes.first(where: isArticle)
        func meta(_ keys: String...) -> String? {
            for key in keys {
                if let tag = raw.meta.first(where: { normalized(key: $0.key) == key && !$0.content.trimmed.isEmpty }) { return tag.content.trimmed }
            }
            return nil
        }
        func linkedData(_ key: String) -> String? { article.flatMap { string(for: key, in: $0) } }

        var resolved = Resolved()
        resolved.sourceURL = [raw.canonicalURL, meta("og:url"), linkedData("url"), linkedData("mainEntityOfPage"), savedFromURL?.absoluteString, raw.baseURL]
            .lazy.compactMap { $0.flatMap(webURL) }.first

        resolved.siteName = first(meta("og:site_name"), article.flatMap { name(of: $0["publisher"], in: nodes) }, meta("application-name"), readability?.siteName)

        let rawTitle = first(
            linkedData("headline"), meta("og:title"), meta("twitter:title"), meta("dc:title"), raw.title, readability?.title, raw.headings.first)
        resolved.title = rawTitle.map { cleanTitle($0, siteName: resolved.siteName, host: resolved.sourceURL?.host, headings: raw.headings) }

        let authors = article.flatMap { authorNames($0["author"], in: nodes) }
        resolved.byline = [authors, meta("author"), meta("dc:creator"), meta("dcterm:creator"), meta("parsely-author"),
                           meta("article:author"), readability?.byline].lazy.compactMap { $0.flatMap(cleanByline) }.first

        resolved.publishedDate = [linkedData("datePublished"), meta("article:published_time"), meta("datepublished"), meta("dc:date"),
                                  meta("parsely-pub-date"), meta("pubdate"), meta("publish_date"), readability?.publishedTime]
            .lazy.compactMap { $0.flatMap(parseDate) }.first { $0 <= now.addingTimeInterval(86_400) }

        let locale = meta("og:locale")?.replacingOccurrences(of: "_", with: "-")
        resolved.language = first(raw.language, linkedData("inLanguage"), locale, meta("content-language"))
        let subtag = resolved.language?.lowercased().split(separator: "-").first.map(String.init)
        resolved.isRightToLeft = raw.direction?.lowercased() == "rtl" || subtag.map(rightToLeftLanguages.contains) == true

        resolved.excerpt = first(meta("og:description"), meta("description"), linkedData("description"), meta("twitter:description"),
                                 meta("dc:description"), readability?.excerpt)
        return resolved
    }

    // MARK: - Titles

    /// Removes the publication's name from a page title ("Story | Daily News" becomes "Story"), and prefers the
    /// page's own heading when the title just adds words around it.
    static func cleanTitle(_ title: String, siteName: String?, host: String?, headings: [String]) -> String {
        let title = title.trimmed
        for heading in headings.map(\.trimmed) where heading.count < title.count && (heading.split(separator: " ").count >= 3 || heading.count >= 15) {
            if TextSimilarity.score(title, heading) >= 0.9 { return heading }
        }
        let segments = title.split(separator: /\s+(?:\||–|—|·|»|::|-)\s+/).map { String($0).trimmed }.filter { !$0.isEmpty }
        guard segments.count > 1 else { return title }

        var names: [String] = []
        if let siteName { names.append(simplified(siteName)) }
        if let host, let label = siteLabel(of: host) { names.append(label) }
        func isSite(_ segment: String) -> Bool {
            let candidate = simplified(segment)
            return names.contains { !$0.isEmpty && !candidate.isEmpty && ($0 == candidate || ($0.count >= 3 && candidate.count >= 3 && ($0.contains(candidate) || candidate.contains($0)))) }
        }
        var remaining = segments
        if isSite(remaining[remaining.count - 1]) { remaining.removeLast() } else if isSite(remaining[0]) { remaining.removeFirst() }
        return remaining.count == segments.count ? title : remaining.joined(separator: " - ")
    }

    private static func simplified(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// "example" for "www.example.com": the longest part of the host that isn't its top-level domain.
    private static func siteLabel(of host: String) -> String? {
        let parts = host.lowercased().split(separator: ".").map(String.init).filter { $0 != "www" }
        return parts.dropLast().max { $0.count < $1.count } ?? parts.first
    }

    // MARK: - Linked data

    private static func jsonLDNodes(_ blocks: [String]) -> [[String: Any]] {
        func flatten(_ value: Any) -> [[String: Any]] {
            if let array = value as? [Any] { return array.flatMap(flatten) }
            guard let node = value as? [String: Any] else { return [] }
            return [node] + (node["@graph"].map(flatten) ?? [])
        }
        return blocks.flatMap { block in
            (try? JSONSerialization.jsonObject(with: Data(block.utf8), options: [.fragmentsAllowed])).map(flatten) ?? []
        }
    }

    private static func types(of node: [String: Any]) -> [String] {
        if let type = node["@type"] as? String { return [type] }
        return (node["@type"] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func isArticle(_ node: [String: Any]) -> Bool {
        types(of: node).contains { $0.hasSuffix("Article") || otherArticleTypes.contains($0) }
    }

    private static func string(for key: String, in node: [String: Any]) -> String? {
        switch node[key] {
        case let text as String: text.trimmed.isEmpty ? nil : text.trimmed
        case let object as [String: Any]: (object["@id"] as? String) ?? (object["url"] as? String)
        default: nil
        }
    }

    /// A name written as text, as an object with a `name`, or as a reference to another node by `@id`.
    private static func name(of value: Any?, in nodes: [[String: Any]]) -> String? {
        switch value {
        case let text as String: return text.trimmed.isEmpty ? nil : text.trimmed
        case let object as [String: Any]:
            if let name = object["name"] as? String, !name.trimmed.isEmpty { return name.trimmed }
            if let id = object["@id"] as? String, let target = nodes.first(where: { ($0["@id"] as? String) == id }) {
                return (target["name"] as? String)?.trimmed
            }
            return nil
        default: return nil
        }
    }

    private static func authorNames(_ value: Any?, in nodes: [[String: Any]]) -> String? {
        let people = (value as? [Any]) ?? value.map { [$0] } ?? []
        let names = people.compactMap { name(of: $0, in: nodes) }.filter { !isURL($0) }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    // MARK: - Values

    private static func normalized(key: String) -> String {
        key.lowercased().replacingOccurrences(of: ".", with: ":").replacingOccurrences(of: "dcterms:", with: "dcterm:")
    }

    private static func first(_ values: String?...) -> String? {
        values.lazy.compactMap { $0?.trimmed }.first { !$0.isEmpty }
    }

    private static func isURL(_ text: String) -> Bool {
        text.contains("://") || text.lowercased().hasPrefix("www.")
    }

    private static func cleanByline(_ text: String) -> String? {
        var byline = text.replacing(/\s+/, with: " ").trimmed
        if let match = byline.prefixMatch(of: /(?i)by\s*:?\s+/) { byline = String(byline[match.range.upperBound...]).trimmed }
        return byline.isEmpty || byline.count > 100 || isURL(byline) ? nil : byline
    }

    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private static func parseDate(_ text: String) -> Date? {
        let text = text.trimmed
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime], [.withFullDate]] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
