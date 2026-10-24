import Foundation
import Testing
@testable import MacReaderKit

/// Each case puts junk in the same container as the article, marked in a way Readability's own class-name and
/// inline-style checks don't catch, and expects the junk gone and the article kept.
@MainActor
struct JunkFilterTests {
    private static let filler = String(repeating: "The quick brown fox jumps over the lazy dog, again and again. ", count: 8)
    private static let junkText = "JUNKMARKER lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore."

    private func extractedText(_ inside: String, head: String = "", outside: String = "") async throws -> String {
        let html = """
            <!DOCTYPE html><html><head><title>T</title>\(head)</head><body>
            <div id="wrap"><article><p>\(Self.filler)</p>\(inside)<p>\(Self.filler)</p><p>\(Self.filler)</p></article></div>\(outside)
            </body></html>
            """
        let payload = try await WebPageExtractor.extract(html: html, baseURL: URL(string: "file:///tmp/p.html")!)
        return try #require(payload.readability).content.textContent
    }

    private func expectJunkRemoved(_ inside: String, head: String = "", outside: String = "", sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let text = try await extractedText(inside, head: head, outside: outside)
        #expect(text.contains("quick brown fox"), sourceLocation: sourceLocation)
        #expect(!text.contains("JUNKMARKER"), sourceLocation: sourceLocation)
    }

    @Test func removesElementsHiddenByAStylesheet() async throws {
        try await expectJunkRemoved("<div class=\"sneaky\"><p>\(Self.junkText)</p></div>", head: "<style>.sneaky { display: none }</style>")
    }

    @Test func removesElementsWithHiddenVisibility() async throws {
        try await expectJunkRemoved("<div class=\"ghost\"><p>\(Self.junkText)</p></div>", head: "<style>.ghost { visibility: hidden }</style>")
    }

    @Test func removesFixedPositionOverlays() async throws {
        try await expectJunkRemoved(
            "<div class=\"layer\"><p>\(Self.junkText)</p></div>",
            head: "<style>.layer { position: fixed; bottom: 0; left: 0; z-index: 999 }</style>")
    }

    @Test func removesCookieConsentBoxes() async throws {
        try await expectJunkRemoved("<div class=\"cookie-consent\"><p>\(Self.junkText)</p></div>")
    }

    @Test func removesNewsletterSignups() async throws {
        try await expectJunkRemoved("<section id=\"newsletter-signup\"><p>\(Self.junkText)</p></section>")
    }

    @Test func removesRecommendedReadingRails() async throws {
        try await expectJunkRemoved("<div class=\"recommended-reading\"><p>\(Self.junkText)</p></div>")
    }

    @Test func removesMoreStoriesByPhrase() async throws {
        try await expectJunkRemoved("<div class=\"more-stories\"><p>\(Self.junkText)</p></div>")
    }

    @Test func removesAdsByStandardSize() async throws {
        try await expectJunkRemoved("<div class=\"slot-300x250\"><p>\(Self.junkText)</p></div>")
    }

    @Test func removesAdsByDataAttribute() async throws {
        try await expectJunkRemoved("<div data-ad-slot=\"top\"><p>\(Self.junkText)</p></div>")
    }

    @Test func removesInsAdsbygoogle() async throws {
        try await expectJunkRemoved("<ins class=\"adsbygoogle\">\(Self.junkText)</ins>")
    }

    @Test func removesLandmarkRolesThatReadabilityKeeps() async throws {
        try await expectJunkRemoved("<div role=\"contentinfo\"><p>\(Self.junkText)</p></div>")
    }

    @Test func removesFormsWithInputs() async throws {
        try await expectJunkRemoved("<form action=\"/join\"><p>\(Self.junkText)</p><input type=\"email\"><button>Go</button></form>")
    }

    @Test func removesPaywallPrompts() async throws {
        try await expectJunkRemoved("<div class=\"paywall-prompt\"><p>\(Self.junkText)</p></div>")
    }

    @Test func matchesWholeWordsOnly() async throws {
        let text = try await extractedText("<div class=\"download-area headline-address\"><p>Download this useful paragraph, which belongs to the article body proper and then some more words.</p></div>")
        #expect(text.contains("Download this useful paragraph"))
    }

    @Test func neverRemovesAContainerHoldingTheArticle() async throws {
        let html = """
            <!DOCTYPE html><html><head><title>T</title></head><body>
            <div class="promo-wrapper cookie-theme"><p>\(Self.filler)</p><p>\(Self.filler)</p><p>\(Self.filler)</p></div>
            </body></html>
            """
        let payload = try await WebPageExtractor.extract(html: html, baseURL: URL(string: "file:///tmp/p.html")!)
        #expect(try #require(payload.readability).content.textContent.contains("quick brown fox"))
    }

    @Test func keepsAsidesInsideTheArticleAsCallouts() async throws {
        let html = """
            <!DOCTYPE html><html><head><title>T</title></head><body><article><p>\(Self.filler)</p>
            <aside><p>CALLOUTMARKER a worthwhile note, with enough words to count as real text for the page.</p></aside>
            <p>\(Self.filler)</p><p>\(Self.filler)</p></article></body></html>
            """
        let payload = try await WebPageExtractor.extract(html: html, baseURL: URL(string: "file:///tmp/p.html")!)
        let content = try #require(payload.readability).content
        #expect(content.textContent.contains("CALLOUTMARKER"))
        func hasCalloutMark(_ node: HTMLNode) -> Bool {
            node.tag == "mr-callout" && node.textContent.contains("CALLOUTMARKER") || node.children.contains(where: hasCalloutMark)
        }
        #expect(hasCalloutMark(content))
    }

    @Test func turnsMonospacedPreformattedDivsIntoCodeBlocks() async throws {
        let html = """
            <!DOCTYPE html><html><head><title>T</title></head><body><article><p>\(Self.filler)</p>
            <div id="snippet" style="font-family: monospace; white-space: pre">let x = 1
            let y = 2</div><p>\(Self.filler)</p><p>\(Self.filler)</p></article></body></html>
            """
        let content = try #require(try await WebPageExtractor.extract(html: html, baseURL: URL(string: "file:///tmp/p.html")!).readability).content
        func snippet(_ node: HTMLNode) -> HTMLNode? { node.tag == "pre" ? node : node.children.lazy.compactMap(snippet).first }
        let node = try #require(snippet(content))
        #expect(node.textContent.contains("let y = 2"))
        #expect(node.attributes["data-mr-mono"] == "1")
    }
}
