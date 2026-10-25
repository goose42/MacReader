import Foundation

/// Tidying of the text that book metadata arrives in.
enum EbookText {
    /// Runs of whitespace collapsed to one space; nil if nothing is left.
    static func clean(_ text: String) -> String? {
        let cleaned = text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Whether a language tag such as `ar` or `he-IL` is one written from right to left.
    static func isRightToLeft(language: String?) -> Bool {
        language?.split(separator: "-").first.map { MetadataResolver.rightToLeftLanguages.contains($0.lowercased()) } == true
    }

    /// A description that was written as HTML, as plain text: paragraph and line-break tags become spaces, the rest
    /// vanish, and entities are decoded.
    static func plain(fromMarkup text: String) -> String? {
        let spaced = text.replacing(/<\/?(?:p|br|div|li|h[1-6])\b[^>]*>/.ignoresCase(), with: " ")
        return clean(HTMLEntities.decode(spaced.replacing(/<[^>]+>/, with: "")))
    }
}
