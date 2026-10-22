import CoreGraphics
import Foundation

/// PDFKit reads text that sits side by side as one line, so a table row can arrive as a single line spanning
/// several cells. This cuts such lines at the columns' boundaries, one fragment per cell.
enum TableSplitter {
    /// - Parameter characterBounds: where each character of the line sits on its page, or nil if unknown.
    static func split(
        _ lines: [TextLine], tables: [TableGrid], characterBounds: (TextLine) -> [CGRect]?
    ) -> [TextLine] {
        lines.flatMap { line -> [TextLine] in
            let center = CGPoint(x: line.bounds.midX, y: line.bounds.midY)
            guard let grid = tables.first(where: { $0.pageIndex == line.pageIndex && $0.region.contains(center) }) else { return [line] }
            let boundaries = grid.columnBoundaries.filter { $0 > line.bounds.minX + 1 && $0 < line.bounds.maxX - 1 }
            guard !boundaries.isEmpty, let rects = characterBounds(line), rects.count == line.text.count else { return [line] }
            return fragments(of: line, rects: rects, boundaries: boundaries)
        }
    }

    private static func fragments(of line: TextLine, rects: [CGRect], boundaries: [CGFloat]) -> [TextLine] {
        // Each character belongs to the column its centre falls in. Spaces have no glyph and so no box: they follow
        // the character before them.
        var column = 0
        var columns: [Int] = []
        for rect in rects {
            if !rect.isEmpty { column = max(column, boundaries.filter { rect.midX >= $0 }.count) }
            columns.append(column)
        }

        let characters = Array(line.text)
        var fragments: [TextLine] = []
        for index in Set(columns).sorted() {
            let members = columns.indices.filter { columns[$0] == index && !characters[$0].isWhitespace }
            guard let first = members.first else { continue }
            let boxes = members.map { rects[$0] }.filter { !$0.isEmpty }
            var fragment = TextLine(
                text: String(members.map { characters[$0] }.enumerated().map { offset, character in
                    // Keep the original spacing between the fragment's own words.
                    offset > 0 && members[offset] > members[offset - 1] + 1 ? " \(character)" : "\(character)"
                }.joined()),
                fontSize: line.fontSize, pageIndex: line.pageIndex,
                bounds: boxes.dropFirst().reduce(boxes.first ?? line.bounds) { $0.union($1) })
            fragment.sourceLocation = line.sourceLocation.map { $0 + first }
            fragments.append(fragment)
        }
        return fragments
    }
}
