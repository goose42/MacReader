import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct WebPageExtractorTests {
    private static let filler = String(repeating: "The quick brown fox jumps over the lazy dog, again and again. ", count: 12)

    private func page(_ body: String, head: String = "") -> String {
        "<!DOCTYPE html><html lang=\"en\"><head><title>T</title>\(head)</head><body>\(body)</body></html>"
    }

    private let base = URL(string: "file:///tmp/page.html")!

    @Test func extractsTheArticleAndLeavesTheChromeBehind() async throws {
        let html = page("""
            <nav><a href="/">Home</a><a href="/about">About</a></nav>
            <article><h1>Headline</h1><p>\(Self.filler)</p><p>\(Self.filler)</p></article>
            <footer>Copyright Somebody</footer>
            """)
        let payload = try await WebPageExtractor.extract(html: html, baseURL: base)
        let text = try #require(payload.readability).content.textContent
        #expect(text.contains("quick brown fox"))
        #expect(!text.contains("Copyright Somebody"))
    }

    @Test func reportsPageMetadata() async throws {
        let html = page(
            "<article><p>\(Self.filler)</p><p>\(Self.filler)</p></article>",
            head: """
                <meta property="og:title" content="Open Graph Title">
                <link rel="canonical" href="https://example.com/post">
                <script type="application/ld+json">{"@type":"Article","headline":"LD Title"}</script>
                """)
        let metadata = try await WebPageExtractor.extract(html: html, baseURL: base).metadata
        #expect(metadata.title == "T")
        #expect(metadata.language == "en")
        #expect(metadata.canonicalURL == "https://example.com/post")
        #expect(metadata.meta.contains(.init(key: "og:title", content: "Open Graph Title")))
        #expect(metadata.jsonLD.first?.contains("LD Title") == true)
    }

    @Test func pageScriptsDoNotRun() async throws {
        let html = page("<article><p id=\"a\">\(Self.filler)</p><p>\(Self.filler)</p></article><script>document.getElementById('a').textContent = 'HACKED'</script>")
        let text = try #require(try await WebPageExtractor.extract(html: html, baseURL: base).readability).content.textContent
        #expect(!text.contains("HACKED"))
    }

    @Test func aPageWithoutTextYieldsNoReadabilityResult() async throws {
        let payload = try await WebPageExtractor.extract(html: page("<div></div>"), baseURL: base)
        #expect(payload.readability == nil)
    }
}
