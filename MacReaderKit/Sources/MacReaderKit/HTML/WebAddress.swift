import Foundation

/// Turns what a person typed or pasted into a web address worth fetching.
public enum WebAddress {
    /// The http(s) address `input` stands for, or nil. A missing scheme is taken to be https, so "example.com/post"
    /// works; a bare word like "notaurl" is not an address.
    public static func parse(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }

        let hasScheme = text.contains("://")
        guard let url = URL(string: hasScheme ? text : "https://\(text)"),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty,
              hasScheme || host.contains(".")
        else { return nil }
        return url
    }

    /// What a library item fetched from `url` is called on disk: its host and path, without query or trailing slash.
    public static func fileName(for url: URL) -> String {
        let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [url.host() ?? "", path].filter { !$0.isEmpty }.joined(separator: "/")
    }
}
