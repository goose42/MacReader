import Foundation

struct OutlineEntry: Equatable, Sendable {
    let label: String
    let level: Int
    let pageIndex: Int
}

/// Turns font-annotated PDF lines into headings and paragraphs.
///
/// Headings come from the PDF's own outline when it has one, otherwise from lines set noticeably larger than body text.
enum StructureBuilder {
    private static let headingScale = 1.25
    private static let maxLevel = 3
    private static let titlePages = 2

    private enum Segment {
        case heading(level: Int, lines: [TextLine])
        case insertedHeading(level: Int, text: String)
        case body([TextLine])
    }

    private struct Run {
        let size: Double
        var lines: [TextLine]
    }

    static func build(lines: [TextLine], fallbackTitle: String, outline: [OutlineEntry] = []) -> ReaderDocument {
        guard !lines.isEmpty else { return ReaderDocument(title: fallbackTitle, blocks: []) }

        var title = fallbackTitle
        let segments: [Segment]
        if outline.isEmpty {
            let result = segmentsBySize(lines)
            segments = result.segments
            if let titleText = result.title { title = titleText }
        } else {
            segments = segmentsByOutline(lines, outline)
        }

        var blocks: [ReaderDocument.Block] = []
        func append(_ kind: ReaderDocument.Block.Kind, _ text: String) {
            guard !text.isEmpty else { return }
            blocks.append(.init(id: blocks.count, kind: kind, text: text))
        }
        for segment in segments {
            switch segment {
            case .heading(let level, let lines): append(.heading(level: level), normalized(lines))
            case .insertedHeading(let level, let text): append(.heading(level: level), text)
            case .body(let lines): append(.paragraph, normalized(lines))
            }
        }
        return ReaderDocument(title: title, blocks: HeadingNumbering.apply(to: blocks))
    }

    // MARK: - Font-size headings

    private static func segmentsBySize(_ lines: [TextLine]) -> (segments: [Segment], title: String?) {
        let bodySize = FontStatistics.bodySize(of: lines)
        let runs = runs(of: lines)
        func isHeading(_ run: Run) -> Bool { run.size >= bodySize * headingScale }

        var headingSizes = Set(runs.filter(isHeading).map(\.size))

        // The document title is the single run at the largest size, if it sits at the very start.
        var titleRun: Int?
        if let largest = headingSizes.max() {
            let candidates = runs.indices.filter { runs[$0].size == largest }
            if candidates.count == 1, runs[candidates[0]].lines[0].pageIndex < titlePages {
                titleRun = candidates[0]
                headingSizes.remove(largest)
            }
        }

        let ranked = headingSizes.sorted(by: >)
        var segments: [Segment] = []
        var title: String?
        for (index, run) in runs.enumerated() {
            if index == titleRun {
                let text = normalized(run.lines)
                title = text.isEmpty ? nil : text
            } else if isHeading(run) {
                let rank = ranked.firstIndex(of: run.size) ?? 0
                segments.append(.heading(level: min(rank + 1, maxLevel), lines: run.lines))
            } else {
                segments.append(.body(run.lines))
            }
        }
        return (segments, title)
    }

    private static func runs(of lines: [TextLine]) -> [Run] {
        var runs: [Run] = []
        for line in lines {
            let size = (line.fontSize * 10).rounded() / 10
            if runs.last?.size == size {
                runs[runs.count - 1].lines.append(line)
            } else {
                runs.append(Run(size: size, lines: [line]))
            }
        }
        return runs
    }

    // MARK: - Outline headings

    private static func segmentsByOutline(_ lines: [TextLine], _ outline: [OutlineEntry]) -> [Segment] {
        // Anchor each entry to the lines that spell its label, or failing that to the start of its page.
        var anchors: [Int: [(level: Int, matched: Int, label: String)]] = [:]
        var searchFrom = 0
        for entry in outline {
            let level = min(max(entry.level, 1), maxLevel)
            if let match = lineSpan(spelling: entry.label, on: entry.pageIndex, in: lines, from: searchFrom) {
                anchors[match.start, default: []].append((level, match.count, entry.label))
                searchFrom = match.start + match.count
            } else {
                let position = lines[searchFrom...].firstIndex { $0.pageIndex >= entry.pageIndex } ?? lines.count
                anchors[position, default: []].append((level, 0, entry.label))
                searchFrom = position
            }
        }

        var segments: [Segment] = []
        var pending: [TextLine] = []
        func flush() {
            if !pending.isEmpty { segments.append(.body(pending)) }
            pending = []
        }
        var index = 0
        while index <= lines.count {
            var consumed = 0
            for anchor in anchors[index] ?? [] {
                flush()
                if anchor.matched > 0 {
                    segments.append(.heading(level: anchor.level, lines: Array(lines[index..<index + anchor.matched])))
                    consumed = max(consumed, anchor.matched)
                } else {
                    segments.append(.insertedHeading(level: anchor.level, text: anchor.label))
                }
            }
            if consumed > 0 {
                index += consumed
            } else {
                if index < lines.count { pending.append(lines[index]) }
                index += 1
            }
        }
        flush()
        return segments
    }

    /// The first run of consecutive lines on `page`, at or after `from`, whose letters and digits spell `label`.
    private static func lineSpan(spelling label: String, on page: Int, in lines: [TextLine], from: Int) -> (start: Int, count: Int)? {
        let target = key(label)
        guard !target.isEmpty else { return nil }
        for start in from..<lines.count where lines[start].pageIndex == page {
            // The printed line may carry a section number the outline label leaves out ("1 Introduction").
            for firstLine in [lines[start].text, withoutLeadingNumber(lines[start].text)] {
                var spelled = key(firstLine)
                var end = start
                while true {
                    if spelled == target { return (start, end - start + 1) }
                    guard target.hasPrefix(spelled), end + 1 < lines.count else { break }
                    end += 1
                    spelled += key(lines[end].text)
                }
            }
        }
        return nil
    }

    private static func withoutLeadingNumber(_ text: String) -> String {
        guard let match = text.firstMatch(of: /^(\d{1,2}(?:\.\d+)*\.?|[IVXLC]+\.)\s+/) else { return text }
        return String(text[match.range.upperBound...])
    }

    // MARK: - Helpers

    private static func normalized(_ lines: [TextLine]) -> String {
        TextNormalizer.normalize(lines.map(\.text).joined(separator: "\n"))
    }

    private static func key(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
