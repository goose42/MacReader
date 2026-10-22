import Foundation

/// Cleans raw PDF-extracted text into readable plaintext.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let dehyphenated = unified.replacingOccurrences(
            of: #"(\p{L})-\n(\p{Ll})"#, with: "$1$2", options: .regularExpression)
        return clean(dehyphenated)
    }

    private static func clean(_ text: String) -> String {
        var paragraphs: [[String]] = [[]]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !paragraphs[paragraphs.count - 1].isEmpty { paragraphs.append([]) }
            } else {
                paragraphs[paragraphs.count - 1].append(line)
            }
        }
        return paragraphs
            .map { $0.joined(separator: " ").replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty && $0.range(of: #"^\d+$"#, options: .regularExpression) == nil }
            .joined(separator: "\n\n")
    }
}
