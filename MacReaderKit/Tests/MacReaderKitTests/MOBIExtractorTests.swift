import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct MOBIExtractorTests {
    private let twoChapters = """
        <html><head></head><body>\
        <p align="center"><font size="7">Chapter One</font></p><p>Call me Ishmael. Some years ago.</p>\
        <mbp:pagebreak/>\
        <p align="center"><font size="7">Chapter Two</font></p><p>More text here.</p>\
        </body></html>
        """

    private func spec(_ markup: String) -> MOBIFixture.Spec {
        var spec = MOBIFixture.Spec()
        spec.text = Data(markup.utf8)
        return spec
    }

    private func write(_ data: Data, named name: String = "\(UUID().uuidString).mobi") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func extract(_ spec: MOBIFixture.Spec) async throws -> EbookExtractor.Result {
        try await EbookExtractor.extract(from: write(MOBIFixture.build(spec)))
    }

    private func failure(_ work: () async throws -> Void) async -> EbookExtractor.Failure? {
        do { try await work() } catch { return error as? EbookExtractor.Failure }
        return nil
    }

    private func summary(_ document: ReaderDocument) -> [String] {
        document.blocks.map { block in
            switch block.kind {
            case .heading(let level): "h\(level): \(block.text)"
            case .paragraph: "p: \(block.text)"
            case .image: "image"
            default: "other: \(block.text)"
            }
        }
    }

    // MARK: Content

    @Test func readsHeadingsAndParagraphs() async throws {
        let result = try await extract(spec(twoChapters))
        #expect(summary(result.document) == [
            "h1: Chapter One", "p: Call me Ishmael. Some years ago.", "h1: Chapter Two", "p: More text here.",
        ])
        #expect(result.format == .mobi)
        #expect(result.document.tableOfContents.map(\.title) == ["Chapter One", "Chapter Two"])
    }

    @Test func compressedRecordsWithTrailingDataReadTheSame() async throws {
        var spec = spec(twoChapters)
        spec.compression = 2
        spec.extraDataFlags = 3
        spec.recordSize = 64
        #expect(summary(try await extract(spec).document).first == "h1: Chapter One")
        #expect(summary(try await extract(spec).document).count == 4)
    }

    @Test func picturesComeFromTheirRecords() async throws {
        var spec = spec(#"<html><body><p>Before.</p><img recindex="00001"/><p>After.</p></body></html>"#)
        spec.images = [makePNG(width: 120, height: 60)]
        let result = try await extract(spec)
        #expect(summary(result.document) == ["p: Before.", "image", "p: After."])
        #expect(result.images.keys.sorted() == ["book-1.png"])
    }

    @Test func aPictureThatIsNotAnImageIsSkipped() async throws {
        var spec = spec(#"<html><body><p>Before.</p><img recindex="00001"/><p>After.</p></body></html>"#)
        spec.images = [Data("not an image".utf8)]
        #expect(summary(try await extract(spec).document) == ["p: Before.", "p: After."])
    }

    @Test func windows1252TextIsDecoded() async throws {
        var spec = MOBIFixture.Spec()
        spec.encoding = 1252
        spec.text = try #require("<html><body><p>Caf\u{E9} au lait.</p></body></html>".data(using: .windowsCP1252))
        #expect(summary(try await extract(spec).document) == ["p: Café au lait."])
    }

    @Test func aContentsPageIsDroppedAndHeadingsKeepTheirText() async throws {
        let template = """
            <html><head><guide><reference type="toc" filepos=@TOC@ /></guide></head><body>\
            <p>Setting out. \(String(repeating: "word ", count: 80))</p>\
            <p>The Road</p><p>Walking on. \(String(repeating: "step ", count: 80))</p>\
            <mbp:pagebreak/>\
            <p><b>Contents</b></p><p><a filepos=@ONE@>The Road</a></p><p><a filepos=@TWO@>The Road</a></p>\
            </body></html>
            """
        var zeroed = template
        for token in ["@TOC@", "@ONE@", "@TWO@"] { zeroed = zeroed.replacingOccurrences(of: token, with: "0000000000") }
        func offset(of needle: String) -> Int {
            zeroed.utf8.distance(from: zeroed.startIndex, to: zeroed.range(of: needle)!.lowerBound)
        }
        var filled = zeroed
        for value in [offset(of: "<p><b>Contents"), offset(of: "<p>The Road"), offset(of: "<p>The Road")] {
            filled.replaceSubrange(filled.range(of: "0000000000")!, with: String(format: "%010d", value))
        }
        let result = try await extract(spec(filled))
        #expect(result.document.plainText.contains("Contents") == false)
        // The only heading level in use is closed up to the first.
        #expect(summary(result.document).contains("h1: The Road"))
    }

    // MARK: Metadata

    @Test func exthFillsTheDocumentHeader() async throws {
        var spec = spec(twoChapters)
        spec.exth = [
            MOBIFixture.exth(503, "The Whale"), MOBIFixture.exth(100, "Herman Melville"), MOBIFixture.exth(100, "Editor Person"),
            MOBIFixture.exth(101, "Harper & Brothers"), MOBIFixture.exth(106, "1851-10-18T04:00:00+00:00"),
            MOBIFixture.exth(524, "en"), MOBIFixture.exth(103, "<p>A <b>whale</b>.</p>"),
        ]
        let document = try await extract(spec).document
        let metadata = try #require(document.metadata)

        #expect(document.title == "The Whale")
        #expect(metadata.byline == "Herman Melville, Editor Person")
        #expect(metadata.siteName == "Harper & Brothers")
        #expect(metadata.publishedDate != nil)
        #expect(metadata.language == "en")
        #expect(metadata.excerpt == "A whale.")
        #expect(!metadata.isRightToLeft)
    }

    @Test func rightToLeftLanguagesAreMarked() async throws {
        var spec = spec(twoChapters)
        spec.exth = [MOBIFixture.exth(524, "ar")]
        #expect(try await extract(spec).document.metadata?.isRightToLeft == true)
    }

    @Test func theTitleFallsBackFromEXTHToTheHeaderToTheDatabaseName() async throws {
        var spec = spec(twoChapters)
        spec.title = "Header Title"
        #expect(try await extract(spec).document.title == "Header Title")

        spec.exth = [MOBIFixture.exth(503, "Updated Title")]
        #expect(try await extract(spec).document.title == "Updated Title")

        // With no name in the header, the Palm database's own name stands in, with its underscores undone.
        spec.exth = []
        spec.title = " "
        #expect(try await extract(spec).document.title == "Test Book")
    }

    // MARK: Failures

    @Test func protectedBooksAreRefused() async throws {
        var spec = spec(twoChapters)
        spec.encryption = 2
        #expect(await failure { _ = try await extract(spec) } == .drmProtected)
    }

    @Test func aBookWithoutTextIsRefused() async throws {
        let spec = spec("<html><body></body></html>")
        #expect(await failure { _ = try await extract(spec) } == .noText)
    }

    @Test func aPlainPalmDocIsNotSupported() async throws {
        let data = PalmFixture.database(type: "TEXt", creator: "REAd", records: [Data(count: 300)])
        let url = try write(data)
        #expect(await failure { _ = try await EbookExtractor.extract(from: url) } == .unsupported)
    }

    @Test func aBrokenKindleFileIsUnreadable() async throws {
        let url = try write(PalmFixture.database(type: "BOOK", creator: "MOBI", records: [Data(count: 300)]))
        #expect(await failure { _ = try await EbookExtractor.extract(from: url) } == .unreadable)
    }

    @Test func anUnknownCompressionIsUnsupported() async throws {
        var spec = spec(twoChapters)
        spec.compression = 3
        #expect(await failure { _ = try await extract(spec) } == .unsupported)
    }
}

@MainActor
struct EbookFormatTests {
    private func temporary(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    @Test func aKindleBookIsRecognisedByItsContents() throws {
        let url = temporary("book.azw")
        try MOBIFixture.build(MOBIFixture.Spec()).write(to: url)
        #expect(EbookExtractor.format(of: url) == .mobi)
    }

    @Test func aZippedEPUBIsRecognisedWhateverItIsCalled() throws {
        let url = temporary("book.dat")
        try EPUBFixture.archive(EPUBFixture.Spec()).write(to: url)
        #expect(EbookExtractor.format(of: url) == .epub)
    }

    @Test func anUnpackedEPUBFolderIsRecognised() throws {
        let url = temporary("Folder.epub")
        try EPUBFixture.write(EPUBFixture.Spec(), to: url)
        #expect(EbookExtractor.format(of: url) == .epub)
    }

    @Test func otherFilesAreNotBooks() throws {
        let pdf = temporary("a.pdf")
        try Data("%PDF-1.7 and more text to fill the header up past sixty-eight bytes in all".utf8).write(to: pdf)
        #expect(EbookExtractor.format(of: pdf) == nil)

        let empty = temporary("empty")
        try Data().write(to: empty)
        #expect(EbookExtractor.format(of: empty) == nil)

        let folder = temporary(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(EbookExtractor.format(of: folder) == nil)

        #expect(EbookExtractor.format(of: temporary("missing.epub")) == nil)
    }

    @Test func somethingUnrecognisedIsUnsupported() async throws {
        let url = temporary("x.bin")
        try Data("whatever".utf8).write(to: url)
        do {
            _ = try await EbookExtractor.extract(from: url)
            Issue.record("expected a failure")
        } catch {
            #expect(error as? EbookExtractor.Failure == .unsupported)
        }
    }
}
