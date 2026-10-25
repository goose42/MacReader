import Foundation

/// Reads a Kindle book (MOBI, AZW, PRC) into a reader document.
enum MOBIExtractor {
    @MainActor
    static func extract(from url: URL) async throws -> EbookExtractor.Result {
        let database: PalmDatabase
        do { database = try PalmDatabase(data: Data(contentsOf: url)) } catch { throw EbookExtractor.Failure.unreadable }
        guard database.isMobipocket else { throw EbookExtractor.Failure.unsupported }

        let book: MOBIBook
        do { book = try MOBIBook(database: database) } catch { throw EbookExtractor.Failure.unreadable }
        guard book.header.encryption == 0 else { throw EbookExtractor.Failure.drmProtected }

        let fallback = url.deletingPathExtension().lastPathComponent
        return try await readOldFormat(book, databaseName: database.name, fallbackTitle: fallback)
    }

    /// An old-format book is one long piece of sloppy HTML, so the browser's parser reads it.
    @MainActor
    private static func readOldFormat(_ book: MOBIBook, databaseName: String, fallbackTitle: String) async throws -> EbookExtractor.Result {
        let text: Data
        do {
            text = try book.text()
        } catch MOBIBook.Failure.unsupportedCompression {
            throw EbookExtractor.Failure.unsupported
        } catch {
            throw EbookExtractor.Failure.unreadable
        }

        let html = MOBI6Markup.prepare(text, encoding: book.header.stringEncoding)
        let parsed: XHTMLParser.Document
        do {
            parsed = try await WebPageExtractor.serializeBody(html: html, baseURL: URL(fileURLWithPath: "/"))
        } catch {
            throw EbookExtractor.Failure.unreadable
        }

        let title = MOBIMetadata.title(of: book.header, databaseName: databaseName, fallback: fallbackTitle)
        let firstImage = book.header.firstImageRecord
        let built = HTMLStructureBuilder.build(
            from: MOBI6Headings.promote(parsed.body), title: title, imagePrefix: "book", dropsRepeatedTitle: false
        ) { address in
            guard address.hasPrefix(MOBI6Markup.imageScheme), let first = firstImage,
                  let number = Int(address.dropFirst(MOBI6Markup.imageScheme.count)), number > 0
            else { return nil }
            return book.record(first + number - 1)
        }
        guard !built.blocks.isEmpty else { throw EbookExtractor.Failure.noText }

        return EbookExtractor.Result(
            document: ReaderDocument(title: title, blocks: built.blocks, metadata: MOBIMetadata.articleMetadata(of: book.header)),
            images: built.images, format: .mobi)
    }
}
