import Foundation

public protocol WordValidator: Sendable {
    func isValid(_ word: String) -> Bool
}

/// Repairs PDFs whose fi/ff/fl ligature glyphs were extracted as stray capitals ("Dle" for "file").
///
/// Which capital stands for which ligature varies per font, so a rule is learned per document:
/// it is accepted when it turns misspelled words into valid ones, and rarely produces non-words.
public struct LigatureRepairer: Sendable {
    private static let candidates: [Character: String] = ["D": "fi", "R": "ff", "S": "fl", "E": "ffi", "F": "ffl"]
    private static let maxMissRatio = 0.3

    private let validator: any WordValidator

    public init(validator: some WordValidator) {
        self.validator = validator
    }

    public func repair(_ lines: [String]) -> [String] {
        let rules = learnRules(from: lines)
        guard !rules.isEmpty else { return lines }
        return lines.map { line in
            line.replacing(#/\p{L}+/#) { match in
                let word = String(match.output)
                return fix(word, rules: rules) ?? word
            }
        }
    }

    // MARK: - Learning

    private func learnRules(from lines: [String]) -> [Character: String] {
        let words = Set(lines.flatMap { $0.matches(of: #/\p{L}+/#).map { String($0.output) } })
            .filter(isSuspect)

        var tallies: [(capital: Character, hits: Int, misses: Int)] = []
        for (capital, replacement) in Self.candidates {
            var hits = 0, misses = 0
            for word in words where word.contains(capital) {
                if validator.isValid(substitute(word, capital, replacement)) {
                    hits += 1
                } else if !validator.isValid(word) {
                    misses += 1  // valid-looking words (e.g. "DataFrame") are never evidence against a rule
                }
            }
            tallies.append((capital, hits, misses))
        }

        // Once one rule is solidly established, the font is known to map ligatures to capitals, so other rules need a
        // single supporting word. Their misses are mostly proper nouns ("Redis"), and a rule can only change a word
        // when its replacement is itself a real word, so that is safe.
        let strong = tallies.filter { $0.hits >= 2 && Self.missRatio($0.hits, $0.misses) <= Self.maxMissRatio }
        let learned = strong.isEmpty ? [] : tallies.filter { $0.hits >= 1 }
        return Dictionary(uniqueKeysWithValues: learned.map { ($0.capital, Self.candidates[$0.capital]!) })
    }

    private static func missRatio(_ hits: Int, _ misses: Int) -> Double {
        Double(misses) / Double(hits + misses)
    }

    // MARK: - Applying

    /// A word worth repairing: it has lowercase letters (so it isn't an acronym) and either isn't a real word or has a
    /// capital after a lowercase letter, which spell checkers tend to wave through ("payoR").
    private func isSuspect(_ word: String) -> Bool {
        word.contains(where: \.isLowercase) && (!validator.isValid(word) || hasInteriorCapital(word))
    }

    private func hasInteriorCapital(_ word: String) -> Bool {
        zip(word, word.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
    }

    private func fix(_ word: String, rules: [Character: String]) -> String? {
        guard isSuspect(word) else { return nil }
        for (capital, replacement) in rules where word.contains(capital) {
            let candidate = substitute(word, capital, replacement)
            if validator.isValid(candidate) { return candidate }
        }
        return nil
    }

    private func substitute(_ word: String, _ capital: Character, _ replacement: String) -> String {
        word.replacingOccurrences(of: String(capital), with: replacement)
    }
}
