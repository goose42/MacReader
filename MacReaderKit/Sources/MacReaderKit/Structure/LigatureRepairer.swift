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

        func accepted(_ tally: (capital: Character, hits: Int, misses: Int), minimumHits: Int) -> Bool {
            tally.hits >= minimumHits && Double(tally.misses) / Double(tally.hits + tally.misses) <= Self.maxMissRatio
        }

        // A single supporting word is enough once another rule shows this font maps ligatures to capitals.
        let strong = tallies.filter { accepted($0, minimumHits: 2) }
        let minimumHits = strong.isEmpty ? 2 : 1
        return Dictionary(uniqueKeysWithValues: tallies
            .filter { accepted($0, minimumHits: minimumHits) }
            .map { ($0.capital, Self.candidates[$0.capital]!) })
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
