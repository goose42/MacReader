import Foundation

public struct ReaderDocument: Codable, Equatable, Sendable {
    public struct Block: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: Codable, Equatable, Sendable {
            case heading(level: Int)
            case paragraph
        }

        public let id: Int
        public let kind: Kind
        public let text: String

        public init(id: Int, kind: Kind, text: String) {
            self.id = id
            self.kind = kind
            self.text = text
        }
    }

    public struct TOCEntry: Equatable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let level: Int

        public init(id: Int, title: String, level: Int) {
            self.id = id
            self.title = title
            self.level = level
        }
    }

    public var title: String
    public var blocks: [Block]

    public init(title: String, blocks: [Block]) {
        self.title = title
        self.blocks = blocks
    }

    public var tableOfContents: [TOCEntry] {
        blocks.compactMap { block in
            guard case .heading(let level) = block.kind else { return nil }
            return TOCEntry(id: block.id, title: block.text, level: level)
        }
    }

    /// Blocks joined by blank lines; the format written to `content.txt`.
    public var plainText: String {
        blocks.map(\.text).joined(separator: "\n\n")
    }
}
