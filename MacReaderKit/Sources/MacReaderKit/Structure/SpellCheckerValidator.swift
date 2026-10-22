import AppKit

/// Validates words with the system spell checker. A word is also valid if lowercasing only its first letter makes it
/// one ("File" at a sentence start). The checker is lenient about odd casing ("payoR" passes), so callers needing to
/// catch those must look at capitalisation themselves.
public struct SpellCheckerValidator: WordValidator {
    public init() {}

    public func isValid(_ word: String) -> Bool {
        isSpelledCorrectly(word) || isSpelledCorrectly(word.prefix(1).lowercased() + word.dropFirst())
    }

    private func isSpelledCorrectly(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        ).location == NSNotFound
    }
}
