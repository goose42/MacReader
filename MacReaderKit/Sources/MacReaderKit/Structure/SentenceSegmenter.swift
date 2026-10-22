import Foundation
import NaturalLanguage

/// Splits text into sentences as UTF-16 ranges.
///
/// `NLTokenizer` proposes the boundaries; a repair pass then rejoins fragments it split after abbreviations
/// ("i.e.", "Dr."), initials, dotted acronyms, or before a lowercase continuation.
enum SentenceSegmenter {
    private static let abbreviations: Set<String> = [
        "i.e.", "e.g.", "cf.", "vs.", "al.", "dr.", "mr.", "mrs.", "ms.", "prof.", "st.", "jr.", "sr.",
        "fig.", "figs.", "eq.", "no.", "vol.", "pp.", "p.", "ch.", "sec.", "approx.", "inc.", "ltd.", "ph.d.",
    ]
    private static let closers: Set<Character> = [")", "]", "”", "’", "\"", "'"]

    static func ranges(in text: String) -> [Range<Int>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let ns = text as NSString

        var pieces: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let trimmed = trim(NSRange(range, in: text), in: ns)
            if trimmed.length > 0 { pieces.append(trimmed) }
            return true
        }

        var merged: [NSRange] = []
        for piece in pieces {
            if let last = merged.last, continues(ns.substring(with: last), into: ns.substring(with: piece)) {
                merged[merged.count - 1] = NSUnionRange(last, piece)
            } else {
                merged.append(piece)
            }
        }
        return merged.map { $0.location..<($0.location + $0.length) }
    }

    /// Whether `next` belongs to the same sentence as `head`, which the tokenizer ended too early.
    private static func continues(_ head: String, into next: String) -> Bool {
        guard let first = next.first else { return false }
        if closers.contains(first) { return true }
        guard head.hasSuffix(".") || head.hasSuffix("…") else { return false }
        if first.isLowercase { return true }

        let word = head.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? head
        if abbreviations.contains(word.lowercased()) { return true }
        if word.range(of: #"^\p{Lu}\.$"#, options: .regularExpression) != nil { return true }
        return word.range(of: #"^(\p{L}\.){2,}$"#, options: .regularExpression) != nil
    }

    private static func trim(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = range.location + range.length
        while start < end, isWhitespace(text.character(at: start)) { start += 1 }
        while end > start, isWhitespace(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(unit) ?? "x")
    }
}
