import Foundation

/// How much of one text's wording another reuses, as Readability measures it when matching a heading to the title.
enum TextSimilarity {
    /// 1 when every word of `other` appears in `text`, falling toward 0 as `other` brings words `text` lacks.
    static func score(_ text: String, _ other: String) -> Double {
        let known = Set(words(in: text))
        let candidate = words(in: other)
        guard !candidate.isEmpty else { return 0 }
        let unseen = candidate.filter { !known.contains($0) }
        return 1 - Double(unseen.joined(separator: " ").count) / Double(candidate.joined(separator: " ").count)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
