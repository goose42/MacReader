import Foundation

/// Bag-of-words precision, recall and F1 between extracted text and its gold standard, the metric extraction
/// benchmarks use. Words are lowercased letters and digits; CJK text, which has no spaces, counts per character.
struct TokenScore {
    let precision: Double
    let recall: Double

    var f1: Double { precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall) }

    init(predicted: String, expected: String) {
        let predictedTokens = Self.tokens(in: predicted)
        let expectedTokens = Self.tokens(in: expected)
        if predictedTokens.isEmpty && expectedTokens.isEmpty {
            precision = 1
            recall = 1
            return
        }
        var remaining = Dictionary(expectedTokens.map { ($0, 1) }, uniquingKeysWith: +)
        var overlap = 0
        for token in predictedTokens where remaining[token, default: 0] > 0 {
            remaining[token]! -= 1
            overlap += 1
        }
        precision = predictedTokens.isEmpty ? 0 : Double(overlap) / Double(predictedTokens.count)
        recall = expectedTokens.isEmpty ? 0 : Double(overlap) / Double(expectedTokens.count)
    }

    static func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        func flush() { if !word.isEmpty { tokens.append(word); word = "" } }
        for character in text.precomposedStringWithCompatibilityMapping.lowercased() {
            if character.unicodeScalars.contains(where: isCJK) {
                flush()
                tokens.append(String(character))
            } else if character.isLetter || character.isNumber {
                word.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF: true
        default: false
        }
    }
}
