import Foundation

public struct LibraryItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let sourceFileName: String
    public let dateAdded: Date
    public let pageCount: Int

    public init(id: UUID, title: String, sourceFileName: String, dateAdded: Date, pageCount: Int) {
        self.id = id
        self.title = title
        self.sourceFileName = sourceFileName
        self.dateAdded = dateAdded
        self.pageCount = pageCount
    }
}
