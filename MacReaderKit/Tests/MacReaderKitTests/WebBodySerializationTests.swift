import Foundation
import Testing
@testable import MacReaderKit

/// The WebKit route into the shared node tree, for markup that isn't well-formed XML: MOBI text and sloppy chapters.
@MainActor
struct WebBodySerializationTests {
    private let base = URL(string: "file:///tmp/book/")!

    private func tags(_ node: HTMLNode) -> [String] {
        node.children.map { $0.isText ? "#text" : $0.tag }
    }

    @Test func tagSoupIsRepairedIntoATree() async throws {
        let document = try await WebPageExtractor.serializeBody(html: "<p>One<p>Two <b>bold<p>Three", baseURL: base)
        #expect(tags(document.body) == ["p", "p", "p"])
        #expect(document.body.children.map(\.textContent) == ["One", "Two bold", "Three"])
    }

    @Test func keepsTheAttributesTheBuilderReadsAndDropsTheRest() async throws {
        let html = #"<p><a href=notes.html#n1 class=ref onclick="evil()" style="x">1</a></p>"#
        let document = try await WebPageExtractor.serializeBody(html: html, baseURL: base)
        let link = try #require(document.body.first { $0.tag == "a" })
        #expect(link.attributes == ["href": "notes.html#n1", "class": "ref"])
    }

    @Test func reportsTitleLanguageAndDirection() async throws {
        let html = #"<html lang="fr" dir="rtl"><head><title> Le Titre </title></head><body><p>x</p></body></html>"#
        let document = try await WebPageExtractor.serializeBody(html: html, baseURL: base)
        #expect(document.title == "Le Titre")
        #expect(document.language == "fr")
        #expect(document.direction == "rtl")
    }

    @Test func pageScriptsDoNotRun() async throws {
        let html = #"<p id="a">Original</p><script>document.getElementById('a').textContent = 'HACKED'</script>"#
        let document = try await WebPageExtractor.serializeBody(html: html, baseURL: base)
        #expect(document.body.textContent.contains("Original"))
        #expect(!document.body.textContent.contains("HACKED"))
    }

    @Test func anSVGCoverBecomesAnImage() async throws {
        let html = """
            <div><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 6 8">\
            <image xlink:href="cover.jpg" width="6" height="8"/></svg></div>
            """
        let document = try await WebPageExtractor.serializeBody(html: html, baseURL: base)
        let picture = try #require(document.body.first { $0.tag == "img" })
        #expect(picture.attributes["src"] == "cover.jpg")
    }
}
