import Foundation

/// A reading cursor that steps through a document one sentence at a time.
///
/// Headings and paragraph sentences are stops; footnotes and empty blocks are skipped. Movement stops at either end.
public struct SentenceNavigator: Equatable, Sendable {
    public struct Position: Equatable, Sendable {
        public let blockID: Int
        public let sentence: Int
    }

    private struct Stop: Equatable, Sendable {
        let position: Position
        let range: Range<Int>
        let blockLength: Int
    }

    private let stops: [Stop]
    private var index: Int

    public init(document: ReaderDocument) {
        stops = document.blocks.flatMap { block in
            block.sentences.enumerated().map { sentence, range in
                Stop(
                    position: Position(blockID: block.id, sentence: sentence),
                    range: range,
                    blockLength: block.text.utf16.count)
            }
        }
        index = 0
    }

    public var current: Position? { stop?.position }

    /// The UTF-16 range of the highlighted sentence within its block.
    public var currentRange: Range<Int>? { stop?.range }

    /// Where the current sentence's midpoint sits within its block, from 0 (top) to 1 (bottom).
    public var scrollAnchor: Double {
        guard let stop, stop.blockLength > 0 else { return 0 }
        return Double(stop.range.lowerBound + stop.range.upperBound) / 2 / Double(stop.blockLength)
    }

    @discardableResult
    public mutating func next() -> Bool { move(to: index + 1) }

    @discardableResult
    public mutating func previous() -> Bool { move(to: index - 1) }

    public func highlight(in blockID: Int) -> Range<Int>? {
        guard let stop, stop.position.blockID == blockID else { return nil }
        return stop.range
    }

    private var stop: Stop? { stops.indices.contains(index) ? stops[index] : nil }

    private mutating func move(to newIndex: Int) -> Bool {
        guard stops.indices.contains(newIndex) else { return false }
        index = newIndex
        return true
    }
}
