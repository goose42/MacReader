import Foundation

/// The generic element-hiding rules of ad-blocker filter lists, indexed so a page can be checked cheaply: plain class
/// and id rules by name, compound rules under their first class or id. Nothing else in a list applies to a saved page.
struct CosmeticFilters: Equatable {
    var classes: [String] = []
    var ids: [String] = []
    /// Compound selectors keyed by their first class (".name") or id ("#name"), which a page must have for them to apply.
    var complex: [String: [String]] = [:]

    var json: Data {
        let object: [String: Any] = ["classes": classes, "ids": ids, "complex": complex]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

enum CosmeticFilterParser {
    private static let maximumSelectorLength = 300

    /// Selectors only an ad blocker's own engine understands, not a browser's selector matching.
    nonisolated(unsafe) private static let procedural =
        /:(?:has-text|contains|xpath|upward|style|remove|matches-css|matches-media|matches-path|nth-ancestor|min-text-length|watch-attr|others|if|if-not|not-ancestor|-abp-[a-z-]+|-ext-[a-z-]+)\b/
    nonisolated(unsafe) private static let plainClass = /\.([A-Za-z0-9_-]+)/
    nonisolated(unsafe) private static let plainID = /#([A-Za-z0-9_-]+)/
    nonisolated(unsafe) private static let firstToken = /[.#][A-Za-z_][A-Za-z0-9_-]*/
    nonisolated(unsafe) private static let attributeSelector = /\[[^\]]*\]/

    static func parse(lists: [String]) -> CosmeticFilters {
        var classes: Set<String> = []
        var ids: Set<String> = []
        var complex: [String: Set<String>] = [:]

        for list in lists {
            for rawLine in list.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                // Only rules with nothing before "##" apply on every site; the rest name a site or are another kind.
                guard line.hasPrefix("##"), !line.hasPrefix("##+js") else { continue }
                let selector = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !selector.isEmpty, selector.count <= maximumSelectorLength, !selector.contains(","),
                      !selector.contains("::"), selector.firstMatch(of: procedural) == nil else { continue }

                if let match = selector.wholeMatch(of: plainClass) {
                    classes.insert(String(match.1))
                } else if let match = selector.wholeMatch(of: plainID) {
                    ids.insert(String(match.1))
                } else if let key = selector.replacing(attributeSelector, with: "").firstMatch(of: firstToken) {
                    complex[String(key.0), default: []].insert(selector)
                }
            }
        }
        return CosmeticFilters(
            classes: classes.sorted(), ids: ids.sorted(), complex: complex.mapValues { $0.sorted() })
    }
}
