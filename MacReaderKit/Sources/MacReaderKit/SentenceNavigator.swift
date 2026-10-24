import Foundation

/// A reading cursor that steps through a document one sentence at a time.
///
/// Headings and paragraph sentences are stops; footnotes and empty blocks are skipped. Movement stops at either end.
public struct SentenceNavigator: Equatable, Sendable {
    public struct Position: Equatable, Codable, Sendable {
        public let blockID: Int
        public let sentence: Int

        public init(blockID: Int, sentence: Int) {
            self.blockID = blockID
            self.sentence = sentence
        }

        private static let scheme = "macreader-sentence"

        /// A link naming this sentence, attached to its text so a click can be traced back to it.
        public var url: URL { URL(string: "\(Self.scheme)://\(blockID)/\(sentence)")! }

        public init?(url: URL) {
            let parts = url.path.split(separator: "/")
            guard url.scheme == Self.scheme, parts.count == 1,
                  let blockID = url.host.flatMap({ Int($0) }), let sentence = Int(parts[0])
            else { return nil }
            self.init(blockID: blockID, sentence: sentence)
        }
    }

    private struct Stop: Equatable, Sendable {
        let position: Position
        let range: Range<Int>
        let blockLength: Int
    }

    private let stops: [Stop]
    private var index: Int

    /// Starts on `start` if it is a reading stop, otherwise on the first stop (a saved position can go stale).
    public init(document: ReaderDocument, startingAt start: Position? = nil) {
        stops = document.blocks.flatMap { block in
            block.sentences.enumerated().map { sentence, range in
                Stop(
                    position: Position(blockID: block.id, sentence: sentence),
                    range: range,
                    blockLength: block.text.utf16.count)
            }
        }
        index = stops.firstIndex { $0.position == start } ?? 0
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

    /// Jumps to `position`. Returns false, leaving the cursor where it was, if that is not a reading stop.
    @discardableResult
    public mutating func move(to position: Position) -> Bool {
        guard let newIndex = stops.firstIndex(where: { $0.position == position }) else { return false }
        return move(to: newIndex)
    }

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
