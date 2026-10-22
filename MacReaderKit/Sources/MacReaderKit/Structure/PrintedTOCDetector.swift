import Foundation

/// Finds and removes a PDF's printed table of contents so the app can build its own.
///
/// A printed contents block is a "Contents" line followed by lines set smaller than body text whose words
/// reappear later in the document (as the headings they point to), interleaved with bare numbers.
enum PrintedTOCDetector {
    private static let searchablePages = 3

    static func strip(_ lines: [TextLine], bodySize: Double) -> [TextLine] {
        guard let start = lines.firstIndex(where: { isContentsLabel($0) && $0.pageIndex < searchablePages }) else {
            return lines
        }

        // The run of small-font lines after the label can hold the entries plus unrelated small print (a tagline).
        let runStart = start + 1
        var runEnd = runStart
        while runEnd < lines.count, lines[runEnd].fontSize < bodySize { runEnd += 1 }

        let laterText = lines[runEnd...].map { normalize($0.text) }.joined()
        var lastEntry: Int?
        for index in runStart..<runEnd where isEntry(lines[index], in: laterText) {
            lastEntry = index
        }
        guard let lastEntry else { return lines }

        var result = lines
        result.removeSubrange(start...lastEntry)
        return result
    }

    private static func isContentsLabel(_ line: TextLine) -> Bool {
        ["contents", "tableofcontents"].contains(normalize(line.text))
    }

    private static func isEntry(_ line: TextLine, in laterText: String) -> Bool {
        let text = normalize(line.text)
        return !text.isEmpty && !text.allSatisfy(\.isNumber) && laterText.contains(text)
    }

    private static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
