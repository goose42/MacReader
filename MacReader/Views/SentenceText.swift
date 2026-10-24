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

    /// The sentence under `point`, allowing for the gap between lines.
    func sentence(at point: CGPoint) -> Int? {
        rects.first { $0.rect.insetBy(dx: 0, dy: -6).contains(point) }?.index
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
            .onTapGesture(coordinateSpace: .local) { point in
                if let index = map.sentence(at: point) { select(index) }
            }
    }
}
