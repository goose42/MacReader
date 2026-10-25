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
            /// A note the PDF sets in small type at the foot of a page, moved to the end of its section.
            case footnote(marker: String)
            /// One item of a web page's list, marked with a bullet or its number and indented by how deeply it nests.
            case listItem(marker: String, depth: Int)
            /// A passage a web page sets as a quotation.
            case quote
            /// Preformatted text, such as program code, with its line breaks and spacing kept.
            case code
            /// The line of text under a figure or table.
            case caption
        }

        public let id: Int
        public let kind: Kind
        public let text: String
        public let numbering: Numbering?
        /// The reading stops within `text`, as UTF-16 offsets. A heading is one stop; boxes, figures, tables and
        /// footnotes have none.
        public let sentences: [Range<Int>]

        public init(id: Int, kind: Kind, text: String, numbering: Numbering? = nil) {
            self.id = id
            self.kind = kind
            self.text = text
            self.numbering = numbering
            self.sentences = Self.readingStops(of: kind, in: text)
        }

        /// Blocks saved before sentence ranges existed derive them from their text; the document's format version
        /// is what gets such items rebuilt.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            kind = try container.decode(Kind.self, forKey: .kind)
            text = try container.decode(String.self, forKey: .text)
            numbering = try container.decodeIfPresent(Numbering.self, forKey: .numbering)
            sentences = try container.decodeIfPresent([Range<Int>].self, forKey: .sentences)
                ?? Self.readingStops(of: kind, in: text)
        }

        private static func readingStops(of kind: Kind, in text: String) -> [Range<Int>] {
            switch kind {
            case .heading: text.isEmpty ? [] : [0..<text.utf16.count]
            case .paragraph, .listItem, .quote: SentenceSegmenter.ranges(in: text)
            case .callout, .image, .table, .footnote, .code, .caption: []
            }
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
    public static let currentFormatVersion = 7

    public var formatVersion: Int
    public var title: String
    public var blocks: [Block]
    /// What a web page says about its article, shown above the text; PDFs have none.
    public var metadata: ArticleMetadata?

    public init(title: String, blocks: [Block], metadata: ArticleMetadata? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.title = title
        self.blocks = blocks
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        title = try container.decode(String.self, forKey: .title)
        blocks = try container.decode([Block].self, forKey: .blocks)
        metadata = try container.decodeIfPresent(ArticleMetadata.self, forKey: .metadata)
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
            switch block.kind {
            case .image: return nil
            case .listItem(let marker, let depth): return String(repeating: "    ", count: depth) + "\(marker) \(block.text)"
            default: break
            }
            guard let numbering = block.numbering else { return block.text }
            return "\(numbering.label) \(block.text)"
        }.joined(separator: "\n\n")
    }
}

/// The facts about a web article that sit beside its text.
public struct ArticleMetadata: Codable, Equatable, Sendable {
    public var byline: String?
    public var siteName: String?
    public var publishedDate: Date?
    public var sourceURL: URL?
    public var language: String?
    public var isRightToLeft: Bool
    public var excerpt: String?

    public init(
        byline: String? = nil, siteName: String? = nil, publishedDate: Date? = nil, sourceURL: URL? = nil,
        language: String? = nil, isRightToLeft: Bool = false, excerpt: String? = nil
    ) {
        self.byline = byline
        self.siteName = siteName
        self.publishedDate = publishedDate
        self.sourceURL = sourceURL
        self.language = language
        self.isRightToLeft = isRightToLeft
        self.excerpt = excerpt
    }
}
