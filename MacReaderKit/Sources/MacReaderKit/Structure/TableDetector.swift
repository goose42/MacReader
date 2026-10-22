import CoreGraphics

/// A table found on a page: where its columns and row rules are, and how far its text reaches above and below them.
struct TableGrid: Equatable, Sendable {
    let pageIndex: Int
    /// Left to right.
    let columns: [ClosedRange<CGFloat>]
    /// Heights of the horizontal rules, top to bottom. Each rule is the top edge of the row beneath it.
    let rules: [CGFloat]
    /// The top of the header text above the first rule, or the first rule when there is none.
    let top: CGFloat
    /// The bottom of the row under the last rule, or the last rule when there is none.
    let bottom: CGFloat

    var hasHeader: Bool { top > rules[0] }

    var region: CGRect {
        CGRect(x: columns[0].lowerBound, y: bottom, width: columns[columns.count - 1].upperBound - columns[0].lowerBound, height: top - bottom)
    }

    /// The x positions that separate one column from the next, midway across the gap between them.
    var columnBoundaries: [CGFloat] {
        zip(columns, columns.dropFirst()).map { ($0.upperBound + $1.lowerBound) / 2 }
    }

    /// Row edges from the top: the header (if any), each ruled row, then the row under the last rule (if any).
    var rowEdges: [CGFloat] {
        var edges = rules
        if hasHeader { edges.insert(top, at: 0) }
        if bottom < rules[rules.count - 1] { edges.append(bottom) }
        return edges
    }
}

/// Finds tables drawn as rows of per-cell rules, the way a browser prints a table with row borders: each row is
/// separated by a line that stops and restarts at every column, so the rules give the columns and the rows at once.
enum TableDetector {
    private static let maxRuleThickness: CGFloat = 3
    private static let minSegmentWidth: CGFloat = 16
    /// Cell borders sit close together; the gap between two cells' rules is a point or two.
    private static let maxCellGap: CGFloat = 6
    private static let sameEdge: CGFloat = 2
    /// Rule levels further apart than this belong to different tables.
    private static let maxRowSpan: CGFloat = 300
    private static let firstGapLimit: CGFloat = 3
    private static let followingGapLimit: CGFloat = 1.8
    private static let sizeTolerance = 0.6

    private struct Level {
        var y: CGFloat
        var segments: [ClosedRange<CGFloat>]
    }

    static func tables(in graphics: PageGraphics, lines: [TextLine]) -> [TableGrid] {
        let levels = ruleLevels(in: graphics)
        var tables: [TableGrid] = []
        for group in groupsOfMatchingLevels(levels) where group.count >= 2 {
            let rules = group.map(\.y)
            let columns = group[0].segments
            let pageLines = lines.filter { $0.pageIndex == graphics.pageIndex && $0.bounds != .zero }
            let (top, bottom) = textExtent(rules: rules, columns: columns, lines: pageLines)
            tables.append(TableGrid(pageIndex: graphics.pageIndex, columns: columns, rules: rules, top: top, bottom: bottom))
        }
        return tables.sorted { $0.top > $1.top }
    }

    // MARK: - Rules

    /// Horizontal rules on the page grouped by height, each level a left-to-right list of segments, top level first.
    private static func ruleLevels(in graphics: PageGraphics) -> [Level] {
        let horizontals: [(y: CGFloat, range: ClosedRange<CGFloat>)] = graphics.rects.compactMap { rect in
            let rect = rect.standardized
            let lower = max(rect.minX, 0), upper = min(rect.maxX, graphics.size.width)
            guard rect.height <= maxRuleThickness, upper - lower >= minSegmentWidth,
                  rect.midY >= 0, rect.midY <= graphics.size.height else { return nil }
            return (rect.midY, lower...upper)
        }.sorted { $0.y > $1.y }

        var levels: [Level] = []
        for rule in horizontals {
            if let last = levels.last, abs(last.y - rule.y) <= sameEdge {
                levels[levels.count - 1].segments = merged(last.segments + [rule.range])
            } else {
                levels.append(Level(y: rule.y, segments: [rule.range]))
            }
        }
        // A level is a row separator only if it breaks at cell borders, so it has several segments with narrow gaps.
        return levels.filter { level in
            level.segments.count >= 2 && zip(level.segments, level.segments.dropFirst()).allSatisfy {
                $1.lowerBound - $0.upperBound <= maxCellGap
            }
        }
    }

    /// Sorted segments with duplicates and overlaps joined, which leaves the 1pt gaps between cells alone.
    private static func merged(_ segments: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var result: [ClosedRange<CGFloat>] = []
        for segment in segments.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, segment.lowerBound < last.upperBound - sameEdge || isSame(segment, last) {
                result[result.count - 1] = min(last.lowerBound, segment.lowerBound)...max(last.upperBound, segment.upperBound)
            } else {
                result.append(segment)
            }
        }
        return result
    }

    private static func isSame(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> Bool {
        abs(a.lowerBound - b.lowerBound) <= sameEdge && abs(a.upperBound - b.upperBound) <= sameEdge
    }

    /// Consecutive levels whose segments break in the same places, which makes them the rows of one table.
    private static func groupsOfMatchingLevels(_ levels: [Level]) -> [[Level]] {
        var groups: [[Level]] = []
        for level in levels {
            if let last = groups.last?.last, last.segments.count == level.segments.count,
               zip(last.segments, level.segments).allSatisfy(isSame), last.y - level.y <= maxRowSpan {
                groups[groups.count - 1].append(level)
            } else {
                groups.append([level])
            }
        }
        return groups
    }

    // MARK: - Text extent

    /// How far the table's text reaches: up to a header above the first rule and down to the row below the last.
    private static func textExtent(rules: [CGFloat], columns: [ClosedRange<CGFloat>], lines: [TextLine]) -> (top: CGFloat, bottom: CGFloat) {
        let left = columns[0].lowerBound - sameEdge, right = columns[columns.count - 1].upperBound + sameEdge
        let inColumns = lines.filter { $0.bounds.midX >= left && $0.bounds.midX <= right }
        let rowSize = dominantSize(of: inColumns.filter { $0.bounds.midY < rules[0] && $0.bounds.midY > rules[rules.count - 1] })

        // A header is no larger than the rows, so a heading above the table is left out.
        let above = inColumns.filter { $0.bounds.midY > rules[0] }.sorted { $0.bounds.minY < $1.bounds.minY }
        let top = reach(from: rules[0], through: above, edge: \.bounds.minY, far: \.bounds.maxY, rowSize: rowSize, sizeFits: { $0 <= rowSize + sizeTolerance })

        let below = inColumns.filter { $0.bounds.midY < rules[rules.count - 1] }.sorted { $0.bounds.maxY > $1.bounds.maxY }
        let bottom = reach(from: rules[rules.count - 1], through: below, edge: \.bounds.maxY, far: \.bounds.minY, rowSize: rowSize, sizeFits: { abs($0 - rowSize) <= sizeTolerance })
        return (top, bottom)
    }

    /// Walks away from a rule over lines that follow one another closely, returning where the last one ends.
    private static func reach(
        from rule: CGFloat, through lines: [TextLine], edge near: KeyPath<TextLine, CGFloat>, far: KeyPath<TextLine, CGFloat>,
        rowSize: Double, sizeFits: (Double) -> Bool
    ) -> CGFloat {
        var reached = rule
        var limit = firstGapLimit
        for line in lines {
            let gap = abs(line[keyPath: near] - reached)
            guard rowSize == 0 || sizeFits(line.fontSize), gap <= limit * line.bounds.height else { break }
            reached = line[keyPath: far]
            limit = followingGapLimit
        }
        return reached
    }

    private static func dominantSize(of lines: [TextLine]) -> Double {
        var counts: [Double: Int] = [:]
        for line in lines { counts[(line.fontSize * 10).rounded() / 10, default: 0] += line.text.count }
        return counts.max { $0.value < $1.value }?.key ?? 0
    }
}
