import Foundation

public struct LibraryItem: Codable, Identifiable, Equatable, Sendable {
    /// What an item was made from. `mobi` covers every Kindle format (MOBI, AZW, AZW3, PRC).
    public enum SourceKind: String, Codable, Sendable { case pdf, html, epub, mobi }

    public let id: UUID
    public let title: String
    public let sourceFileName: String
    public let dateAdded: Date
    public let pageCount: Int
    public let sourceKind: SourceKind
    /// The publication a web page came from, shown under its title in the library.
    public let siteName: String?
    /// Who wrote a book, shown under its title in the library.
    public let author: String?

    public init(
        id: UUID, title: String, sourceFileName: String, dateAdded: Date, pageCount: Int,
        sourceKind: SourceKind = .pdf, siteName: String? = nil, author: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceFileName = sourceFileName
        self.dateAdded = dateAdded
        self.pageCount = pageCount
        self.sourceKind = sourceKind
        self.siteName = siteName
        self.author = author
    }

    /// Items saved before web pages were supported have neither field, and are PDFs; those saved before books were
    /// supported have no author.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        sourceKind = try container.decodeIfPresent(SourceKind.self, forKey: .sourceKind) ?? .pdf
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        author = try container.decodeIfPresent(String.self, forKey: .author)
    }
}
