import AppKit
import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct HTMLTextExtractorTests {
    private static let filler = String(repeating: "The quick brown fox jumps over the lazy dog, again and again. ", count: 10)

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ html: String, named name: String = "Saved Page.html", in folder: URL, encoding: String.Encoding = .utf8) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try html.data(using: encoding)!.write(to: url)
        return url
    }

    private func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func expectFailure(_ expected: HTMLTextExtractor.Failure, extracting url: URL) async {
        do {
            _ = try await HTMLTextExtractor.extract(pageAt: url)
            Issue.record("expected \(expected)")
        } catch {
            #expect(error as? HTMLTextExtractor.Failure == expected)
        }
    }

    @Test func readsAnArticleIntoADocument() async throws {
        let url = try write("""
            <html><head><title>A Fine Post</title></head><body>
            <nav><a href="/">Home</a></nav>
            <article><h1>A Fine Post</h1><h2>First part</h2><p>\(Self.filler)</p><p>\(Self.filler)</p></article>
            </body></html>
            """, in: try folder())
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        #expect(result.document.title == "A Fine Post")
        #expect(result.document.blocks.first.map { $0.text } == "First part")
        #expect(result.document.blocks.contains { $0.text.contains("quick brown fox") })
        #expect(!result.document.plainText.contains("Home"))
    }

    @Test func decodesLegacyCharsets() async throws {
        let url = try write("""
            <html><head><meta charset="windows-1252"><title>Café</title></head><body>
            <article><p>\(Self.filler) Voilà, un café.</p><p>\(Self.filler)</p></article></body></html>
            """, in: try folder(), encoding: .windowsCP1252)
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        #expect(result.document.plainText.contains("un café"))
    }

    @Test func imagesFromTheFilesFolderComeAlong() async throws {
        let directory = try folder()
        let files = directory.appendingPathComponent("Saved Page_files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try png(width: 300, height: 150).write(to: files.appendingPathComponent("photo one.png"))
        let url = try write("""
            <html><head><title>Pictures</title></head><body><article>
            <p>\(Self.filler)</p>
            <figure><img src="Saved Page_files/photo one.png" alt="A photo"><figcaption>The photo.</figcaption></figure>
            <p>\(Self.filler)</p></article></body></html>
            """, in: directory)
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        let kinds = result.document.blocks.map(\.kind)
        guard let image = kinds.compactMap({ kind -> (String, Double)? in
            if case .image(let name, let ratio) = kind { return (name, ratio) }
            return nil
        }).first else { Issue.record("no image block"); return }
        #expect(image.1 == 2)
        #expect(result.images[image.0] != nil)
        #expect(result.document.blocks.contains { $0.kind == .caption && $0.text == "The photo." })
        #expect(result.resourcesFolder?.lastPathComponent == "Saved Page_files")
    }

    @Test func inlineDataImagesAreDecoded() async throws {
        let uri = "data:image/png;base64," + png(width: 100, height: 100).base64EncodedString()
        let url = try write("""
            <html><head><title>Inline</title></head><body><article><p>\(Self.filler)</p><img src="\(uri)"><p>\(Self.filler)</p></article></body></html>
            """, in: try folder())
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        #expect(result.images.count == 1)
    }

    @Test func aPageWithoutAnArticleThrows() async throws {
        let url = try write("<html><body><div></div></body></html>", in: try folder())
        await expectFailure(.noArticle, extracting: url)
    }

    @Test func aMissingFileThrowsUnreadable() async throws {
        let url = try folder().appendingPathComponent("nope.html")
        await expectFailure(.unreadable, extracting: url)
    }

    @Test func theArticleCarriesItsMetadata() async throws {
        let url = try write("""
            <!DOCTYPE html>
            <!-- saved from url=(0033)https://saved.example.com/original -->
            <html lang="en"><head>
            <title>How Bridges Work | Example Times</title>
            <meta property="og:site_name" content="Example Times">
            <meta property="og:description" content="A short summary.">
            <meta name="author" content="Ada Lovelace">
            <meta property="article:published_time" content="2024-05-01T10:30:00Z">
            <link rel="canonical" href="https://www.exampletimes.com/bridges">
            </head><body><article><h1>How Bridges Work</h1><p>\(Self.filler)</p><p>\(Self.filler)</p></article></body></html>
            """, in: try folder())
        let document = try await HTMLTextExtractor.extract(pageAt: url).document
        #expect(document.title == "How Bridges Work")
        let metadata = try #require(document.metadata)
        #expect(metadata.siteName == "Example Times")
        #expect(metadata.byline == "Ada Lovelace")
        #expect(metadata.excerpt == "A short summary.")
        #expect(metadata.language == "en")
        #expect(metadata.sourceURL?.absoluteString == "https://www.exampletimes.com/bridges")
        #expect(metadata.publishedDate == ISO8601DateFormatter().date(from: "2024-05-01T10:30:00Z"))
    }

    @Test func theSavedFromAddressIsUsedWhenThePageNamesNoCanonicalURL() async throws {
        let url = try write("""
            <!DOCTYPE html>
            <!-- saved from url=(0033)https://saved.example.com/original -->
            <html><head><title>Plain</title></head><body><article><p>\(Self.filler)</p><p>\(Self.filler)</p></article></body></html>
            """, in: try folder())
        let metadata = try #require(try await HTMLTextExtractor.extract(pageAt: url).document.metadata)
        #expect(metadata.sourceURL?.host == "saved.example.com")
    }

    @Test func trailingRelatedArticlesAndCopyrightAreCut() async throws {
        let url = try write("""
            <html><head><title>Cut</title></head><body><article>
            <p>First \(Self.filler)</p><p>Second \(Self.filler)</p><p>Third \(Self.filler)</p>
            <h3>Related articles</h3><p>TEASERMARKER another story that is long enough to look like a paragraph of text.</p>
            <p>© 2024 Example. All rights reserved.</p></article></body></html>
            """, in: try folder())
        let text = try await HTMLTextExtractor.extract(pageAt: url).document.plainText
        #expect(text.contains("Third"))
        #expect(!text.contains("TEASERMARKER"))
        #expect(!text.contains("All rights reserved"))
    }

    @Test func aStoryCollapsedBehindReadMoreIsRecoveredFromItsStructuredData() async throws {
        let paragraphs = [
            "The regional government announced on Saturday that the long-delayed harbour bridge would finally open to traffic next month.",
            "Engineers blamed unusually heavy monsoon rains for the setbacks, adding that corroded bearings had to be replaced before inspection.",
            "Local fishermen welcomed the news, saying the new crossing would cut their daily commute to the markets by nearly an hour.",
            "Opposition leaders, however, questioned the final cost, which officials confirmed had risen to almost double the original estimate.",
        ]
        let related = (1...8).map { "<p>Other headline \($0) in the latest stories block, long enough to look like real text.</p>" }.joined()
        let body = paragraphs.joined().replacingOccurrences(of: "'", with: "&#039;")
        let url = try write("""
            <html><head><title>Collapsed</title>
            <style>.readmore ~ * { display: none !important }</style>
            <script type="application/ld+json">{"@type":"NewsArticle","articleBody":"\(body)"}</script></head><body>
            <main><div class="story"><p>\(paragraphs[0])</p><button class="readmore">Read more</button>
            <p>\(paragraphs[1])</p><p>\(paragraphs[2])</p><p>\(paragraphs[3])</p></div>
            <div class="latest-stories-block">\(related)</div></main></body></html>
            """, in: try folder())
        let document = try await HTMLTextExtractor.extract(pageAt: url).document
        for paragraph in paragraphs { #expect(document.plainText.contains(paragraph)) }
        #expect(!document.plainText.contains("Other headline"))
        #expect(document.blocks.filter { $0.kind == .paragraph }.count == 4)
    }
}
