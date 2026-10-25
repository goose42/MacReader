import Foundation

/// Reads a Kindle book (MOBI, AZW, AZW3, PRC) into a reader document. Old-format books are one long piece of sloppy
/// HTML; KF8 books are a set of XHTML files, and a file may hold both, in which case the newer one is read.
enum MOBIExtractor {
    @MainActor
    static func extract(from url: URL) async throws -> EbookExtractor.Result {
        let database: PalmDatabase
        do { database = try PalmDatabase(data: Data(contentsOf: url)) } catch { throw EbookExtractor.Failure.unreadable }
        guard database.isMobipocket else { throw EbookExtractor.Failure.unsupported }

        let first: MOBIBook
        do { first = try MOBIBook(database: database) } catch { throw EbookExtractor.Failure.unreadable }
        let book = newerBook(in: database, after: first) ?? first
        guard first.header.encryption == 0, book.header.encryption == 0 else { throw EbookExtractor.Failure.drmProtected }

        let fallback = url.deletingPathExtension().lastPathComponent
        if book.header.version >= 8 {
            return try await readKF8(book, databaseName: database.name, fallbackTitle: fallback)
        }
        return try await readOldFormat(book, databaseName: database.name, fallbackTitle: fallback)
    }

    /// A file made for both old and new readers holds the old book, a `BOUNDARY` record, then the KF8 book, whose
    /// first record the old book's EXTH header names.
    private static func newerBook(in database: PalmDatabase, after book: MOBIBook) -> MOBIBook? {
        guard book.header.version < 8, let start = book.header.kf8Record, start > 0,
              let newer = try? MOBIBook(database: database, base: start), newer.header.version >= 8
        else { return nil }
        return newer
    }

    // MARK: Old format

    /// An old-format book is one long piece of sloppy HTML, so the browser's parser reads it.
    @MainActor
    private static func readOldFormat(_ book: MOBIBook, databaseName: String, fallbackTitle: String) async throws -> EbookExtractor.Result {
        let text = try text(of: book)
        let html = MOBI6Markup.prepare(text, encoding: book.header.stringEncoding)
        let parsed: XHTMLParser.Document
        do {
            parsed = try await WebPageExtractor.serializeBody(html: html, baseURL: URL(fileURLWithPath: "/"))
        } catch {
            throw EbookExtractor.Failure.unreadable
        }
        return try document(
            from: MOBI6Headings.promote(parsed.body), book: book, databaseName: databaseName, fallbackTitle: fallbackTitle)
    }

    // MARK: KF8

    /// A KF8 book is a set of XHTML files, read as an EPUB's chapters are.
    @MainActor
    private static func readKF8(_ book: MOBIBook, databaseName: String, fallbackTitle: String) async throws -> EbookExtractor.Result {
        let kf8: KF8Book
        do {
            kf8 = try KF8Book(book: book)
        } catch MOBIBook.Failure.unsupportedCompression {
            throw EbookExtractor.Failure.unsupported
        } catch {
            throw EbookExtractor.Failure.unreadable
        }

        var chapters: [HTMLNode] = []
        for part in kf8.parts {
            guard let body = await ChapterReader.body(of: part.data) else { continue }
            chapters.append(HTMLNode(
                tag: "section", attributes: ["data-mr-chapter": part.title ?? ""],
                children: body.children.map { ChapterReader.resolvingPictures(in: $0, using: kf8.pictureAddress(for:)) }))
        }
        return try document(
            from: HTMLNode(tag: "body", children: chapters), book: book, databaseName: databaseName, fallbackTitle: fallbackTitle)
    }

    // MARK: Shared

    private static func text(of book: MOBIBook) throws -> Data {
        do {
            return try book.text()
        } catch MOBIBook.Failure.unsupportedCompression {
            throw EbookExtractor.Failure.unsupported
        } catch {
            throw EbookExtractor.Failure.unreadable
        }
    }

    /// Builds the blocks from the book's tree. Pictures are addressed `mobi-image:<n>`, the nth after the first
    /// picture record.
    @MainActor
    private static func document(
        from root: HTMLNode, book: MOBIBook, databaseName: String, fallbackTitle: String
    ) throws -> EbookExtractor.Result {
        let title = MOBIMetadata.title(of: book.header, databaseName: databaseName, fallback: fallbackTitle)
        let firstImage = book.header.firstImageRecord
        let built = HTMLStructureBuilder.build(from: root, title: title, imagePrefix: "book", dropsRepeatedTitle: false) { address in
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
