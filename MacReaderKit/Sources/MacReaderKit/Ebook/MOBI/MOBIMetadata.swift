import Foundation

/// What a Kindle book says about itself in its EXTH records.
enum MOBIMetadata {
    /// The book's name: the updated title if it has one, else the full name in its header, else the database's name.
    static func title(of header: MOBIHeader, databaseName: String, fallback: String) -> String {
        EbookText.clean(header.string(503) ?? "")
            ?? EbookText.clean(header.fullName)
            ?? EbookText.clean(databaseName.replacingOccurrences(of: "_", with: " "))
            ?? fallback
    }

    static func articleMetadata(of header: MOBIHeader) -> ArticleMetadata {
        var seen: Set<String> = []
        let authors = header.strings(100).filter { seen.insert($0).inserted }
        let language = header.string(524).flatMap(EbookText.clean)
        return ArticleMetadata(
            byline: authors.isEmpty ? nil : authors.joined(separator: ", "),
            siteName: header.string(101).flatMap(EbookText.clean),
            publishedDate: EbookDate.parse(header.string(106)),
            language: language,
            isRightToLeft: EbookText.isRightToLeft(language: language),
            excerpt: header.string(103).flatMap(EbookText.plain(fromMarkup:)))
    }
}
