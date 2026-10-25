import Foundation

/// Decodes the character references (`&#039;`, `&amp;`) that HTML-escaped text such as JSON-LD carries.
enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}", "mdash": "—", "ndash": "–",
        "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "copy": "©", "reg": "®", "trade": "™",
        "laquo": "«", "raquo": "»", "bull": "•", "middot": "·",
    ]

    /// One pass only, so `&amp;lt;` becomes `&lt;`. References it doesn't know are left as written.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacing(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);/) { match in
            let name = String(match.1)
            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.0)
            }
            return named[name] ?? String(match.0)
        }
    }
}
