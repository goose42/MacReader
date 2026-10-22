import Foundation

public struct ReaderDocument: Codable, Equatable, Sendable {
    public struct Block: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: Codable, Equatable, Sendable {
            case heading(level: Int)
            case paragraph
            /// Text the PDF sets in a box of its own, outside the linear flow.
            case callout
            /// A picture or figure, saved as `name` in the item's images folder; its `text` is empty.
            case image(name: String, aspectRatio: Double)
            /// Rows of cells; its `text` is the same cells tab- and newline-separated.
            case table(Table)
        }

        public let id: Int
        public let kind: Kind
        public let text: String
        public let numbering: Numbering?

        public init(id: Int, kind: Kind, text: String, numbering: Numbering? = nil) {
            self.id = id
            self.kind = kind
            self.text = text
            self.numbering = numbering
        }

        /// A table block, with its tab-separated text derived from the cells.
        public static func table(id: Int, rows: [[String]], hasHeader: Bool) -> Block {
            Block(
                id: id, kind: .table(Table(rows: rows, hasHeader: hasHeader)),
                text: rows.map { $0.joined(separator: "\t") }.joined(separator: "\n"))
        }
    }

    /// A grid of text cells as the PDF laid them out.
    public struct Table: Codable, Equatable, Sendable {
        public var rows: [[String]]
        /// Whether the first row is a header.
        public var hasHeader: Bool

        public init(rows: [[String]], hasHeader: Bool) {
            self.rows = rows
            self.hasHeader = hasHeader
        }
    }

    /// A heading's section number as printed in the PDF, kept apart from the heading text.
    public struct Numbering: Codable, Equatable, Sendable {
        public enum Placement: String, Codable, Sendable {
            /// Set on the same line as the heading ("2.1 Methods").
            case inline
            /// Set on a line of its own above the heading ("MODULE 1").
            case eyebrow
        }

        public let label: String
        public let placement: Placement

        public init(label: String, placement: Placement) {
            self.label = label
            self.placement = placement
        }
    }

    public struct TOCEntry: Equatable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let level: Int
        public let numbering: Numbering?

        public init(id: Int, title: String, level: Int, numbering: Numbering? = nil) {
            self.id = id
            self.title = title
            self.level = level
            self.numbering = numbering
        }
    }

    /// Bumped when extraction changes what `document.json` holds, so older items are rebuilt from their PDF.
    public static let currentFormatVersion = 4

    public var formatVersion: Int
    public var title: String
    public var blocks: [Block]

    public init(title: String, blocks: [Block]) {
        self.formatVersion = Self.currentFormatVersion
        self.title = title
        self.blocks = blocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        title = try container.decode(String.self, forKey: .title)
        blocks = try container.decode([Block].self, forKey: .blocks)
    }

    public var tableOfContents: [TOCEntry] {
        blocks.compactMap { block in
            guard case .heading(let level) = block.kind else { return nil }
            return TOCEntry(id: block.id, title: block.text, level: level, numbering: block.numbering)
        }
    }

    /// Ids of the numbered headings that start a new top-level section, which the reader sets off with a rule.
    /// That is the shallowest level carrying numbers; the very first block never needs one.
    public var sectionBreaks: Set<Int> {
        let numbered = blocks.compactMap { block -> (id: Int, level: Int)? in
            guard case .heading(let level) = block.kind, block.numbering != nil else { return nil }
            return (block.id, level)
        }
        guard let shallowest = numbered.map(\.level).min() else { return [] }
        let firstID = blocks.first?.id
        return Set(numbered.filter { $0.level == shallowest && $0.id != firstID }.map(\.id))
    }

    /// Names of the image files the document's figures refer to, in reading order.
    public var imageNames: [String] {
        blocks.compactMap { block in
            guard case .image(let name, _) = block.kind else { return nil }
            return name
        }
    }

    /// Blocks joined by blank lines, headings prefixed with their numbers; the format written to `content.txt`.
    public var plainText: String {
        blocks.compactMap { block in
            if case .image = block.kind { return nil }
            guard let numbering = block.numbering else { return block.text }
            return "\(numbering.label) \(block.text)"
        }.joined(separator: "\n\n")
    }
}
