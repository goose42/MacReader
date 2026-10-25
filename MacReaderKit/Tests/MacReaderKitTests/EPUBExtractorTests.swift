import AppKit
import Foundation
import Testing
@testable import MacReaderKit

func makePNG(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

struct EbookDateTests {
    private func components(_ text: String?) -> [Int]? {
        guard let date = EbookDate.parse(text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return [parts.year!, parts.month!, parts.day!]
    }

    @Test func readsFullAndPartialDates() {
        #expect(components("1851-10-18") == [1851, 10, 18])
        #expect(components(" 2020-05-17T10:30:00Z ") == [2020, 5, 17])
        #expect(components("2020-05") == [2020, 5, 1])
        #expect(components("2020") == [2020, 1, 1])
    }

    @Test func anythingElseIsNoDate() {
        #expect(components("sometime in spring") == nil)
        #expect(components("") == nil)
        #expect(components(nil) == nil)
    }
}

@MainActor
struct EPUBExtractorTests {
    private func summary(_ document: ReaderDocument) -> [String] {
        document.blocks.map { block in
            switch block.kind {
            case .heading(let level): "h\(level): \(block.text)"
            case .paragraph: "p: \(block.text)"
            case .footnote(let marker): "footnote \(marker): \(block.text)"
            case .image: "image"
            case .listItem(let marker, _): "li \(marker): \(block.text)"
            case .table: "table"
            default: "other: \(block.text)"
            }
        }
    }

    /// What `work` throws, if it throws an `EbookExtractor.Failure`.
    private func failure(_ work: () async throws -> Void) async -> EbookExtractor.Failure? {
        do { try await work() } catch { return error as? EbookExtractor.Failure }
        return nil
    }

    private func extract(_ spec: EPUBFixture.Spec) async throws -> EbookExtractor.Result {
        try await EPUBExtractor.extract(from: EPUBFixture.writeArchive(spec))
    }

    private var twoChapters: EPUBFixture.Spec {
        var spec = EPUBFixture.Spec()
        spec.title = "The Whale"
        spec.chapters = [
            .init(file: "ch1.xhtml", navTitle: "Loomings", body: "<h2>Loomings</h2><p>Call me Ishmael. Some years ago.</p>"),
            .init(file: "ch2.xhtml", navTitle: "The Carpet-Bag", body: "<p>I stuffed a shirt or two into my bag.</p>"),
        ]
        return spec
    }

    // MARK: Content

    @Test func readsChaptersInOrderWithTheirTitles() async throws {
        let result = try await extract(twoChapters)
        #expect(summary(result.document) == [
            "h1: Loomings", "p: Call me Ishmael. Some years ago.",
            "h1: The Carpet-Bag", "p: I stuffed a shirt or two into my bag.",
        ])
        #expect(result.document.title == "The Whale")
        #expect(result.document.tableOfContents.map(\.title) == ["Loomings", "The Carpet-Bag"])
        #expect(result.format == .epub)
    }

    @Test func aChapterMissingFromTheContentsGetsNoInventedTitle() async throws {
        var spec = twoChapters
        spec.chapters.append(.init(file: "ch3.xhtml", navTitle: nil, body: "<p>Epilogue text.</p>"))
        let result = try await extract(spec)
        #expect(summary(result.document).suffix(1) == ["p: Epilogue text."])
    }

    @Test func nonLinearChaptersComeLast() async throws {
        var spec = twoChapters
        spec.chapters[0].linear = false
        let result = try await extract(spec)
        #expect(result.document.tableOfContents.map(\.title) == ["The Carpet-Bag", "Loomings"])
    }

    @Test func aBookFromAnEPUB2ReadsTheSame() async throws {
        var spec = twoChapters
        spec.version = "2.0"
        let result = try await extract(spec)
        #expect(result.document.tableOfContents.map(\.title) == ["Loomings", "The Carpet-Bag"])
    }

    @Test func anUnpackedBookReadsTheSame() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub", isDirectory: true)
        try EPUBFixture.write(twoChapters, to: folder)
        let fromFolder = try await EPUBExtractor.extract(from: folder)
        let fromZip = try await extract(twoChapters)
        #expect(fromFolder.document == fromZip.document)
    }

    @Test func footnotesLandAtTheEndOfTheirChapterAndMarkersLeaveTheText() async throws {
        var spec = twoChapters
        spec.chapters[0].body = """
            <h2>Loomings</h2>
            <p>Call me Ishmael.<a epub:type="noteref" href="notes.xhtml#n1">1</a> Some years ago.</p>
            <aside epub:type="footnote" id="n1"><p>1. A name, not a promise.</p></aside>
            <p>Never mind how long precisely.</p>
            """
        let result = try await extract(spec)
        #expect(summary(result.document).prefix(4) == [
            "h1: Loomings", "p: Call me Ishmael. Some years ago.", "p: Never mind how long precisely.",
            "footnote 1: A name, not a promise.",
        ])
    }

    @Test func picturesAreSavedAndReferencedFromTheirChapter() async throws {
        var spec = twoChapters
        spec.extraFiles["OEBPS/images/whale.png"] = makePNG(width: 120, height: 60)
        spec.chapters[1].body = "<p>Before.</p><img src=\"images/whale.png\" alt=\"A whale\"/><p>After.</p>"
        let result = try await extract(spec)
        #expect(summary(result.document).suffix(3) == ["p: Before.", "image", "p: After."])
        #expect(result.images.keys.sorted() == ["book-1.png"])
        #expect(result.document.imageNames == ["book-1.png"])
    }

    @Test func aCoverDrawnAsAnSVGIsAPicture() async throws {
        var spec = twoChapters
        spec.extraFiles["OEBPS/cover.png"] = makePNG(width: 100, height: 150)
        spec.chapters.insert(.init(file: "cover.xhtml", navTitle: "Cover", body: """
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 150">\
            <image xlink:href="cover.png" width="100" height="150"/></svg>
            """), at: 0)
        let result = try await extract(spec)
        #expect(summary(result.document).prefix(2) == ["h1: Cover", "image"])
    }

    @Test func listsAndTablesComeThrough() async throws {
        var spec = twoChapters
        spec.chapters[1].body = """
            <ul><li>First</li><li>Second</li></ul>
            <table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>
            """
        let result = try await extract(spec)
        #expect(summary(result.document).suffix(3) == ["li •: First", "li •: Second", "table"])
    }

    @Test func entitiesFromTheXHTMLDTDAreUnderstood() async throws {
        var spec = twoChapters
        spec.chapters[1].body = "<p>Caf&eacute;&nbsp;&mdash; naïve.</p>"
        let result = try await extract(spec)
        #expect(summary(result.document).last == "p: Café — naïve.")
    }

    @Test func aChapterThatIsNotWellFormedStillReads() async throws {
        var spec = twoChapters
        spec.chapters[1].body = "<p>First para<p>Second para with <b>bold<br>and a break"
        let result = try await extract(spec)
        let text = result.document.plainText
        #expect(text.contains("First para"))
        #expect(text.contains("Second para with bold"))
    }

    @Test func chapterFilesAreTheOnlySpineItemsRead() async throws {
        var spec = twoChapters
        spec.extraFiles["OEBPS/pic.png"] = makePNG(width: 50, height: 50)
        spec.editPackage = {
            $0.replacingOccurrences(of: "</manifest>", with: "<item id=\"pic\" href=\"pic.png\" media-type=\"image/png\"/></manifest>")
                .replacingOccurrences(of: "</spine>", with: "<itemref idref=\"pic\"/></spine>")
        }
        let result = try await extract(spec)
        #expect(result.document.tableOfContents.map(\.title) == ["Loomings", "The Carpet-Bag"])
    }

    // MARK: Metadata

    @Test func metadataFillsTheDocumentHeader() async throws {
        var spec = twoChapters
        spec.authors = ["Herman Melville", "Editor Person"]
        spec.publisher = "Harper & Brothers"
        spec.date = "1851-10-18"
        spec.language = "en"
        spec.description = "<p>A whale.</p>"
        let metadata = try #require(try await extract(spec).document.metadata)
        #expect(metadata.byline == "Herman Melville, Editor Person")
        #expect(metadata.siteName == "Harper & Brothers")
        #expect(metadata.publishedDate != nil)
        #expect(metadata.language == "en")
        #expect(metadata.excerpt == "A whale.")
        #expect(!metadata.isRightToLeft)
    }

    @Test func rightToLeftBooksAreMarked() async throws {
        var spec = twoChapters
        spec.rightToLeft = true
        #expect(try await extract(spec).document.metadata?.isRightToLeft == true)
        var arabic = twoChapters
        arabic.language = "ar"
        #expect(try await extract(arabic).document.metadata?.isRightToLeft == true)
    }

    @Test func aBookWithoutATitleIsNamedAfterItsFile() async throws {
        var spec = twoChapters
        spec.editPackage = { $0.replacingOccurrences(of: "<dc:title id=\"t1\">The Whale</dc:title>", with: "") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Some Book.epub")
        try EPUBFixture.archive(spec).write(to: url)
        #expect(try await EPUBExtractor.extract(from: url).document.title == "Some Book")
    }

    // MARK: Failures

    @Test func protectedBooksAreRefused() async throws {
        var spec = twoChapters
        spec.extraFiles["META-INF/rights.xml"] = Data("<rights/>".utf8)
        #expect(await failure { _ = try await extract(spec) } == .drmProtected)
    }

    @Test func obfuscatedFontsDoNotStopABook() async throws {
        var spec = twoChapters
        spec.encryptionXML = """
            <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
            <enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
            <enc:CipherData><enc:CipherReference URI="OEBPS/f.otf"/></enc:CipherData></enc:EncryptedData></encryption>
            """
        #expect(try await extract(spec).document.blocks.isEmpty == false)
    }

    @Test func aBookWithoutTextIsRefused() async throws {
        var spec = twoChapters
        spec.chapters = [.init(file: "ch1.xhtml", navTitle: "Empty", body: "<div></div>")]
        spec.navigationOverride = EPUBFixture.xhtml("<p>x</p>")
        #expect(await failure { _ = try await extract(spec) } == .noText)
    }

    @Test func aFileThatIsNotABookIsUnreadable() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        try Data("not a zip".utf8).write(to: url)
        #expect(await failure { _ = try await EPUBExtractor.extract(from: url) } == .unreadable)
    }
}
