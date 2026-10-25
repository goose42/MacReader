import Foundation

/// Paths inside a book, which are written the way URLs are: relative to the file that mentions them, with
/// percent-escapes, fragments and the occasional `..`.
enum EPUBPath {
    /// The path, from the root of the book, of the file `href` points at when written in the file at `base`; nil for
    /// addresses that leave the book (`https:`, `data:`, `mailto:`). A bare `#fragment` points at `base` itself.
    /// A path that climbs above the root stops at the root.
    static func resolve(_ href: String, relativeTo base: String) -> String? {
        let address = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:/) == nil else { return nil }

        var path = address
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        if path.isEmpty { return base }
        path = path.removingPercentEncoding ?? path

        var parts: [Substring] = path.hasPrefix("/") ? [] : Array(base.split(separator: "/").dropLast())
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// The part of `href` after `#`, unescaped.
    static func fragment(of href: String) -> String? {
        guard let hash = href.firstIndex(of: "#") else { return nil }
        let fragment = String(href[href.index(after: hash)...])
        return fragment.isEmpty ? nil : (fragment.removingPercentEncoding ?? fragment)
    }
}
