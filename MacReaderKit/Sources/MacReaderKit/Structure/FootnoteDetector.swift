import Foundation

/// Lifts footnotes out of the body lines so the paragraphs they interrupted can run on across the page break.
///
/// A footnote is the run of lines set smaller than body text at the very bottom of a page, starting with a marker
/// (a number or one of `* † ‡ § ¶`). Smaller lines after a marker belong to the same note.
enum FootnoteDetector {
    struct Note: Equatable {
        let marker: String
        let lines: [TextLine]
        /// Index into the returned body lines of the first line after the note's page.
        let anchor: Int
    }

    private static let sizeScale = 0.9
    private static let markerPattern = #"^(\d{1,3}(?!\d)|[*†‡§¶]+)"#

    static func split(_ lines: [TextLine], bodySize: Double) -> (body: [TextLine], notes: [Note]) {
        var body: [TextLine] = []
        var notes: [Note] = []
        var index = 0
        while index < lines.count {
            let page = lines[index].pageIndex
            var end = index
            while end < lines.count, lines[end].pageIndex == page { end += 1 }
            let pageLines = Array(lines[index..<end])
            index = end

            var tailStart = pageLines.count
            while tailStart > 0, pageLines[tailStart - 1].fontSize < bodySize * sizeScale { tailStart -= 1 }
            let tail = Array(pageLines[tailStart...])

            body += pageLines[..<tailStart]
            guard let first = tail.first, marked(first) != nil else {
                body += tail
                continue
            }
            for note in group(tail) { notes.append(Note(marker: note.marker, lines: note.lines, anchor: body.count)) }
        }
        return (body, notes)
    }

    private static func group(_ tail: [TextLine]) -> [(marker: String, lines: [TextLine])] {
        var notes: [(marker: String, lines: [TextLine])] = []
        for line in tail {
            if let (marker, rest) = marked(line) {
                let stripped = TextLine(text: rest, fontSize: line.fontSize, pageIndex: line.pageIndex)
                notes.append((marker, [stripped]))
            } else {
                notes[notes.count - 1].lines.append(line)
            }
        }
        return notes
    }

    private static func marked(_ line: TextLine) -> (marker: String, rest: String)? {
        guard let range = line.text.range(of: markerPattern, options: .regularExpression) else { return nil }
        let rest = line.text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (String(line.text[range]), rest)
    }
}
