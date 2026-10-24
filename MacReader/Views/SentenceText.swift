import SwiftUI

/// Marks a stretch of text as one sentence so the renderer can report where it was laid out.
private struct SentenceTag: TextAttribute {
    let index: Int
}

/// Where each sentence of a block was last laid out, so a click can be traced back to its sentence.
final class SentenceHitMap: @unchecked Sendable {
    private var rects: [(index: Int, rect: CGRect)] = []

    fileprivate func reset() { rects.removeAll() }
    fileprivate func add(_ rect: CGRect, for index: Int) { rects.append((index, rect)) }

    /// The sentence under `point`; a click in the gap between lines or past a line's end goes to the closest one.
    func sentence(at point: CGPoint) -> Int? {
        rects.min { distance(from: point, to: $0.rect) < distance(from: point, to: $1.rect) }.flatMap {
            distance(from: point, to: $0.rect) <= 12 ? $0.index : nil
        }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

private struct SentenceRenderer: TextRenderer {
    let map: SentenceHitMap

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        map.reset()
        for line in layout {
            for run in line {
                if let tag = run[SentenceTag.self] { map.add(run.typographicBounds.rect, for: tag.index) }
            }
            context.draw(line)
        }
    }
}

extension Text {
    /// `text` split into its sentences (UTF-16 ranges), each tagged so a click can be traced back to it.
    init(_ text: AttributedString, sentences: [Range<Int>]) {
        var result = Text("")
        var cursor = 0
        func append(_ range: Range<Int>, tag: Int?) {
            guard !range.isEmpty, let slice = Range(NSRange(location: range.lowerBound, length: range.count), in: text) else { return }
            let part = Text(AttributedString(text[slice]))
            result = result + (tag.map { part.customAttribute(SentenceTag(index: $0)) } ?? part)
        }
        for (index, range) in sentences.enumerated() {
            append(cursor..<max(cursor, range.lowerBound), tag: nil)
            append(range, tag: index)
            cursor = max(cursor, range.upperBound)
        }
        append(cursor..<max(cursor, text.characters.reduce(0) { $0 + String($1).utf16.count }), tag: nil)
        self = result
    }
}

extension View {
    /// Calls `select` with the index of the sentence that was clicked. Dragging still selects text.
    func onSentenceClick(_ select: @escaping (Int) -> Void) -> some View {
        modifier(SentenceClick(select: select))
    }
}

private struct SentenceClick: ViewModifier {
    let select: (Int) -> Void
    @State private var map = SentenceHitMap()

    func body(content: Content) -> some View {
        content
            .textRenderer(SentenceRenderer(map: map))
            // Simultaneous, because the text selection that `.textSelection` installs would otherwise take the click.
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local).onEnded { tap in
                    if let index = map.sentence(at: tap.location) { select(index) }
                })
    }
}
