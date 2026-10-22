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
    private static let minBoxLines = 2
    private static let minSingleLineBoxWidth: CGFloat = 300
    /// Lines of a wrapped paragraph run close to the full width of their box.
    private static let proseFill: CGFloat = 0.8

    private enum Segment {
        case heading(level: Int, lines: [TextLine])
        case insertedHeading(level: Int, text: String)
        case body([TextLine])
    }

    private struct Run {
        let size: Double
        var lines: [TextLine]
    }

    /// Text inside a box becomes a callout and figures become image blocks; both are placed where they sit in
    /// reading order, splitting a paragraph if one runs past them. Everything else flows as before.
    static func build(
        lines allLines: [TextLine], fallbackTitle: String, outline: [OutlineEntry] = [],
        boxes: [PageBox] = [], figures: [Figure] = []
    ) -> ReaderDocument {
        guard !allLines.isEmpty else { return ReaderDocument(title: fallbackTitle, blocks: []) }

        var allLines = allLines
        for index in allLines.indices { allLines[index].sequence = index }
        let (lines, visuals) = separateVisuals(allLines, boxes: boxes, figures: figures)

        var title = fallbackTitle
        var segments: [Segment] = []
        if !lines.isEmpty {
            if outline.isEmpty {
                let result = segmentsBySize(lines)
                segments = result.segments
                if let titleText = result.title { title = titleText }
            } else {
                segments = segmentsByOutline(lines, outline)
            }
        }

        var blocks: [ReaderDocument.Block] = []
        func append(_ kind: ReaderDocument.Block.Kind, _ text: String) {
            if case .image = kind {} else { guard !text.isEmpty else { return } }
            blocks.append(.init(id: blocks.count, kind: kind, text: text))
        }
        var pending = visuals.sorted { $0.anchor < $1.anchor }[...]
        func appendVisuals(before sequence: Int) {
            while let visual = pending.first, visual.anchor <= sequence {
                append(visual.kind, visual.text)
                pending.removeFirst()
            }
        }
        for segment in segments {
            switch segment {
            case .heading(let level, let lines):
                if let first = lines.first { appendVisuals(before: first.sequence) }
                append(.heading(level: level), normalized(lines))
            case .insertedHeading(let level, let text):
                append(.heading(level: level), text)
            case .body(var lines):
                // A box or figure can land mid-paragraph, which then continues after it.
                while let visual = pending.first, let last = lines.last, visual.anchor <= last.sequence {
                    let before = lines.prefix { $0.sequence < visual.anchor }
                    if !before.isEmpty { append(.paragraph, normalized(Array(before))) }
                    append(visual.kind, visual.text)
                    pending.removeFirst()
                    lines.removeFirst(before.count)
                }
                append(.paragraph, normalized(lines))
            }
        }
        appendVisuals(before: Int.max)
        return ReaderDocument(title: title, blocks: HeadingNumbering.apply(to: blocks))
    }

    // MARK: - Boxes and figures

    private struct Visual {
        let anchor: Int
        let kind: ReaderDocument.Block.Kind
        let text: String
    }

    /// Splits off the lines that sit inside a box, returning the remaining flow and a visual for every box with
    /// text and every figure. A visual's anchor is the sequence number of the line it should appear before.
    private static func separateVisuals(
        _ lines: [TextLine], boxes: [PageBox], figures: [Figure]
    ) -> (flow: [TextLine], visuals: [Visual]) {
        var members: [[TextLine]] = Array(repeating: [], count: boxes.count)
        var flow: [TextLine] = []
        for line in lines {
            let center = CGPoint(x: line.bounds.midX, y: line.bounds.midY)
            if line.bounds != .zero,
               let index = boxes.firstIndex(where: { $0.pageIndex == line.pageIndex && $0.rect.contains(center) }) {
                members[index].append(line)
            } else {
                flow.append(line)
            }
        }

        var visuals: [Visual] = []
        for (box, boxLines) in zip(boxes, members) where !boxLines.isEmpty {
            // A short highlight behind part of one line is inline emphasis (code, a marker), not a box.
            guard boxLines.count >= minBoxLines || box.rect.width >= minSingleLineBoxWidth else {
                flow += boxLines
                continue
            }
            visuals.append(Visual(anchor: boxLines[0].sequence, kind: .callout, text: calloutText(boxLines, in: box.rect)))
        }
        flow.sort { $0.sequence < $1.sequence }
        for figure in figures {
            let below = flow.first {
                ($0.pageIndex == figure.pageIndex && $0.bounds.midY < figure.rect.midY) || $0.pageIndex > figure.pageIndex
            }
            let ratio = figure.rect.height > 0 ? Double(figure.rect.width / figure.rect.height) : 1
            visuals.append(Visual(
                anchor: below?.sequence ?? Int.max, kind: .image(name: figure.name, aspectRatio: ratio), text: ""))
        }
        return (flow, visuals)
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

    /// Wrapped prose reflows like any paragraph. Anything ragged (code, a table, a list) keeps the PDF's line breaks,
    /// with each line's indentation rebuilt from how far it sits right of the least indented line.
    private static func calloutText(_ lines: [TextLine], in box: CGRect) -> String {
        let wrapped = lines.dropLast()
        let isProse = wrapped.allSatisfy { $0.bounds.width >= box.width * proseFill }
        guard lines.count > 1, !isProse else { return normalized(lines) }

        let left = lines.map(\.bounds.minX).min() ?? 0
        let widths = lines.map { $0.bounds.width / CGFloat(max($0.text.count, 1)) }.sorted()
        let characterWidth = widths[widths.count / 2]
        return lines.map { line in
            let indent = characterWidth > 0 ? Int(((line.bounds.minX - left) / characterWidth).rounded()) : 0
            return String(repeating: " ", count: max(indent, 0)) + line.text
        }.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func normalized(_ lines: [TextLine]) -> String {
        TextNormalizer.normalize(lines.map(\.text).joined(separator: "\n"))
    }

    private static func key(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
