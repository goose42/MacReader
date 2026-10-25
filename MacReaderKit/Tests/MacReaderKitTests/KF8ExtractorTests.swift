import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct KF8ExtractorTests {
    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).azw3")
        try data.write(to: url)
        return url
    }

    private func extract(_ spec: KF8Fixture.Spec) async throws -> EbookExtractor.Result {
        try await EbookExtractor.extract(from: write(KF8Fixture.build(spec)))
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
            case .footnote(let marker): "footnote \(marker): \(block.text)"
            case .image: "image"
            default: "other: \(block.text)"
            }
        }
    }

    private var twoChapters: KF8Fixture.Spec {
        var spec = KF8Fixture.Spec()
        spec.parts = [
            .init(fragments: ["<h1>Loomings</h1><p>Call me Ishmael. Some years ago.</p>"], title: "Loomings"),
            .init(fragments: ["<p>I stuffed a shirt</p>", "<p>or two into my bag.</p>"], title: "The Carpet-Bag"),
        ]
        return spec
    }

    @Test func readsChaptersWithTheirTitles() async throws {
        let result = try await extract(twoChapters)
        #expect(summary(result.document) == [
            "h1: Loomings", "p: Call me Ishmael. Some years ago.",
            "h1: The Carpet-Bag", "p: I stuffed a shirt", "p: or two into my bag.",
        ])
        #expect(result.format == .mobi)
        #expect(result.document.title == "A KF8 Book")
        #expect(result.document.tableOfContents.map(\.title) == ["Loomings", "The Carpet-Bag"])
    }

    @Test func aFileWithoutContentsStillReadsFromItsOwnHeadings() async throws {
        var spec = twoChapters
        spec.parts[0].title = nil
        spec.parts[1].title = nil
        spec.parts[1].fragments = ["<h2>Second</h2><p>Text.</p>"]
        #expect(try await extract(spec).document.tableOfContents.map(\.title) == ["Loomings", "Second"])
    }

    @Test func compressedRecordsWithTrailingDataReadTheSame() async throws {
        var spec = twoChapters
        spec.recordSize = 64
        spec.extraDataFlags = 3
        #expect(summary(try await extract(spec).document).count == 5)
    }

    @Test func picturesAreFoundThroughTheirEmbedAddress() async throws {
        var spec = twoChapters
        spec.images = [makePNG(width: 120, height: 60)]
        spec.parts[1].fragments = ["<p>Before.</p>", #"<img src="kindle:embed:0001?mime=image/jpeg"/>"#]
        let result = try await extract(spec)
        #expect(summary(result.document).suffix(2) == ["p: Before.", "image"])
        #expect(result.images.keys.sorted() == ["book-1.png"])
    }

    @Test func aPictureDrawnInAnSVGFlowIsFound() async throws {
        var spec = twoChapters
        spec.images = [makePNG(width: 80, height: 80), makePNG(width: 90, height: 90)]
        spec.flows = ["<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'><image xlink:href='kindle:embed:0002?mime=image/jpeg'/></svg>"]
        spec.parts[1].fragments = [#"<img src="kindle:flow:0001?mime=image/svg+xml"/>"#]
        let result = try await extract(spec)
        #expect(result.document.imageNames.count == 1)
        #expect(result.images.count == 1)
    }

    @Test func notesTypedAsFootnotesEndTheirChapter() async throws {
        var spec = twoChapters
        spec.parts[0].fragments = [
            "<h1>Loomings</h1><p>Call me Ishmael.<a epub:type='noteref' href='#n1'>1</a> Some years ago.</p>",
            "<aside epub:type='footnote' id='n1'><p>1. A name, not a promise.</p></aside><p>Never mind.</p>",
        ]
        let blocks = summary(try await extract(spec).document)
        #expect(blocks.prefix(4) == ["h1: Loomings", "p: Call me Ishmael. Some years ago.", "p: Never mind.", "footnote 1: A name, not a promise."])
    }

    @Test func aFileThatIsNotWellFormedStillReads() async throws {
        var spec = twoChapters
        spec.parts[1].fragments = ["<p>First para<p>Second para with <b>bold<br>and a break"]
        let text = try await extract(spec).document.plainText
        #expect(text.contains("First para"))
        #expect(text.contains("Second para with bold"))
    }

    @Test func metadataComesFromTheKF8Header() async throws {
        var spec = twoChapters
        spec.exth = [MOBIFixture.exth(100, "Herman Melville"), MOBIFixture.exth(524, "en"), MOBIFixture.exth(503, "Moby-Dick")]
        let document = try await extract(spec).document
        #expect(document.title == "Moby-Dick")
        #expect(document.metadata?.byline == "Herman Melville")
        #expect(document.metadata?.language == "en")
    }

    // MARK: Joint files

    @Test func aFileWithBothFormatsIsReadAsKF8() async throws {
        var old = MOBIFixture.Spec(title: "Old Title")
        old.text = Data("<html><body><p>This is the old format.</p></body></html>".utf8)
        var spec = twoChapters
        spec.joint = old
        let result = try await extract(spec)
        let text = result.document.plainText
        #expect(text.contains("Call me Ishmael"))
        #expect(!text.contains("old format"))
        #expect(result.document.title == "A KF8 Book")
    }

    @Test func protectionOnEitherHalfIsRefused() async throws {
        var old = MOBIFixture.Spec()
        old.encryption = 2
        var spec = twoChapters
        spec.joint = old
        #expect(await failure { _ = try await extract(spec) } == .drmProtected)

        var protected = twoChapters
        protected.encryption = 2
        #expect(await failure { _ = try await extract(protected) } == .drmProtected)
    }

    // MARK: Failures

    @Test func aBookWithNothingToReadIsRefused() async throws {
        var spec = KF8Fixture.Spec()
        spec.parts = [.init(fragments: ["<div></div>"])]
        #expect(await failure { _ = try await extract(spec) } == .noText)
    }

    @Test func aBookWhoseIndexesAreMissingIsUnreadable() async throws {
        var header = MOBIFixture.Spec()
        header.version = 8
        let record = MOBIFixture.firstRecord(
            header, textRecordCount: 1, textLength: 5, huffmanRecord: 0, huffmanCount: 0, firstImage: 0xFFFF_FFFF,
            kf8: MOBIFixture.KF8Indexes())
        let url = try write(PalmFixture.database(records: [record, Data("text".utf8)]))
        #expect(await failure { _ = try await EbookExtractor.extract(from: url) } == .unreadable)
    }

    @Test func anUnknownCompressionIsUnsupported() async throws {
        var spec = twoChapters
        spec.compression = 3
        #expect(await failure { _ = try await extract(spec) } == .unsupported)
    }
}
