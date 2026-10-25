import Foundation

/// Prepares the text of an old-format Kindle book for a browser's parser. That text is HTML of the 1990s, with a few
/// extensions of its own, and it addresses places in itself by byte offset (`filepos`).
///
/// - The contents page the book ends with, which Kindles jump to, is dropped, as the printed contents page of a
///   PDF is; the offsets in its links are where the headings start, so those elements are marked.
/// - `<mbp:pagebreak/>`, which a browser would take as an element wrapping everything after it, becomes a rule.
/// - Pictures, which name a record (`recindex`), are addressed as `mobi-image:<n>`.
enum MOBI6Markup {
    static let headingAttribute = "data-mr-heading"
    static let imageScheme = "mobi-image:"

    static func prepare(_ text: Data, encoding: String.Encoding) -> String {
        var bytes = [UInt8](text)
        let page = contentsPage(in: bytes, encoding: encoding)
        bytes = rewrite(bytes, marking: page?.headingOffsets ?? [], removing: page?.range)

        var html = String(data: Data(bytes), encoding: encoding) ?? String(decoding: bytes, as: UTF8.self)
        html = html.replacing(/<mbp:pagebreak\s*\/?>(?:\s*<\/mbp:pagebreak>)?/.ignoresCase(), with: "<hr data-mr-pagebreak=\"1\">")
        html = html.replacing(/<img\b([^>]*?)\brecindex\s*=\s*["']?(\d+)["']?/.ignoresCase()) { match in
            "<img\(match.1)src=\"\(imageScheme)\(Int(match.2) ?? 0)\""
        }
        html = html.replacing(/<img\b(?![^>]*mobi-image:)([^>]*?)\bhirecindex\s*=\s*["']?(\d+)["']?/.ignoresCase()) { match in
            "<img\(match.1)src=\"\(imageScheme)\(Int(match.2) ?? 0)\""
        }
        return html
    }

    // MARK: Contents page

    private struct ContentsPage {
        /// The bytes of the page, from its first tag to the next page break.
        var range: Range<Int>
        /// The offsets its links point at.
        var headingOffsets: [Int]
    }

    /// The page the book's `<guide>` calls its table of contents, when that page is a list of links to the book's own
    /// parts. A page that is mostly prose, or most of the book, is left alone.
    private static func contentsPage(in bytes: [UInt8], encoding: String.Encoding) -> ContentsPage? {
        guard let start = guideContentsOffset(in: bytes), start < bytes.count, bytes[start] == UInt8(ascii: "<") else { return nil }

        let end = find("<mbp:pagebreak", in: bytes, from: start + 1) ?? find("</body>", in: bytes, from: start + 1) ?? bytes.count
        guard end > start, (end - start) * 10 <= bytes.count * 4 else { return nil }

        let page = String(data: Data(bytes[start..<end]), encoding: encoding) ?? String(decoding: bytes[start..<end], as: UTF8.self)
        let offsets = page.matches(of: /<a\b[^>]*?\bfilepos\s*=\s*["']?0*(\d+)/.ignoresCase()).compactMap { Int($0.1) }
        guard offsets.count >= 2 else { return nil }

        let linked = page.matches(of: /<a\b[^>]*>(.*?)<\/a>/.ignoresCase().dotMatchesNewlines()).reduce(0) { $0 + visibleLength(String($1.1)) }
        let total = visibleLength(page)
        guard total > 0, Double(linked) / Double(total) >= 0.5 else { return nil }
        return ContentsPage(range: start..<end, headingOffsets: offsets)
    }

    /// Where the `<reference type="toc" filepos=…>` in the book's `<guide>` points. The guide is at the top, and
    /// ASCII, so the first bytes are read as Latin-1 whatever the book's encoding.
    private static func guideContentsOffset(in bytes: [UInt8]) -> Int? {
        let head = String(bytes: bytes.prefix(16_384), encoding: .isoLatin1) ?? ""
        for tag in head.matches(of: /<reference\b[^>]*>/.ignoresCase()) {
            let text = String(tag.0)
            guard text.firstMatch(of: /type\s*=\s*["']?toc/.ignoresCase()) != nil,
                  let position = text.firstMatch(of: /filepos\s*=\s*["']?0*(\d+)/.ignoresCase())
            else { continue }
            return Int(position.1)
        }
        return nil
    }

    private static func visibleLength(_ markup: String) -> Int {
        markup.replacing(/<[^>]*>/, with: "").replacing(/\s+/, with: "").count
    }

    /// Copies `bytes`, leaving out `removed` and marking the tag that starts at each of `offsets`. An offset that
    /// isn't the start of a tag is ignored.
    private static func rewrite(_ bytes: [UInt8], marking offsets: [Int], removing removed: Range<Int>?) -> [UInt8] {
        guard !offsets.isEmpty || removed != nil else { return bytes }
        let mark = Array(" \(headingAttribute)=\"1\"".utf8)
        let delimiters: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D, 0x2F, 0x3E]

        var insertions: Set<Int> = []
        for offset in Set(offsets) where offset >= 0 && offset + 1 < bytes.count && removed?.contains(offset) != true {
            guard bytes[offset] == UInt8(ascii: "<"), (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(bytes[offset + 1] | 0x20) else { continue }
            var nameEnd = offset + 1
            while nameEnd < bytes.count, !delimiters.contains(bytes[nameEnd]) { nameEnd += 1 }
            insertions.insert(nameEnd)
        }

        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if let removed, index == removed.lowerBound {
                index = removed.upperBound
                continue
            }
            if insertions.contains(index) { output.append(contentsOf: mark) }
            output.append(bytes[index])
            index += 1
        }
        return output
    }

    /// The first place at or after `start` where `needle` (lowercase ASCII) occurs, ignoring case.
    private static func find(_ needle: String, in bytes: [UInt8], from start: Int) -> Int? {
        let pattern = Array(needle.utf8)
        guard start >= 0, bytes.count >= pattern.count else { return nil }
        func lowercased(_ byte: UInt8) -> UInt8 { (0x41...0x5A).contains(byte) ? byte | 0x20 : byte }
        var index = start
        while index + pattern.count <= bytes.count {
            if (0..<pattern.count).allSatisfy({ lowercased(bytes[index + $0]) == pattern[$0] }) { return index }
            index += 1
        }
        return nil
    }
}
