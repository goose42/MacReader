import Foundation
import Testing
@testable import MacReaderKit

struct ContentArbiterTests {
    private static func words(_ count: Int, _ seed: String = "word") -> String {
        (0..<count).map { "\(seed)\($0 % 7)" }.joined(separator: " ")
    }

    private func paragraph(_ text: String) -> HTMLNode { el("p", [:], .text(text)) }

    private func readability(_ children: HTMLNode...) -> ReadabilityResult {
        ReadabilityResult(content: HTMLNode(tag: "div", children: children), title: nil, byline: nil, excerpt: nil, siteName: nil, publishedTime: nil)
    }

    private func payload(readability: ReadabilityResult?, body: HTMLNode?, jsonLD: [String] = []) -> ExtractionPayload {
        var metadata = RawMetadata()
        metadata.jsonLD = jsonLD
        var payload = ExtractionPayload(readability: readability, metadata: metadata)
        payload.body = body
        return payload
    }

    @Test func keepsReadabilityWhenNothingBeatsIt() throws {
        let article = paragraph(Self.words(200))
        let body = el("body", [:], el("article", [:], paragraph(Self.words(210))))
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(article), body: body)))
        #expect(choice.source == .readability)
    }

    @Test func prefersTheArticleElementWhenReadabilityKeptLessThanHalfOfIt() throws {
        let short = paragraph(Self.words(60))
        let body = el("body", [:], el("div", [:], el("article", [:], paragraph(Self.words(150)), paragraph(Self.words(150)), paragraph(Self.words(150)))))
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(short), body: body)))
        #expect(choice.source == .semantic)
        #expect(choice.content.textContent.contains("word6"))
        #expect(choice.content.textLength > short.textLength * 2)
    }

    @Test func aLongerCandidateFullOfLinksDoesNotWin() throws {
        let article = paragraph(Self.words(150))
        let links = (0..<40).map { el("a", ["href": "/\($0)"], .text("link number \($0) with several words in it ")) }
        let body = el("body", [:], el("article", [:], paragraph(Self.words(150)), HTMLNode(tag: "div", children: links)))
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(article), body: body)))
        #expect(choice.source == .readability)
    }

    @Test func aLongerCandidateThatLacksWhatReadabilityFoundDoesNotWin() throws {
        let story = paragraph(Self.words(150, "story"))
        let body = el("body", [:], el("article", [:], paragraph(Self.words(500, "sidebar"))))
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(story), body: body)))
        #expect(choice.source == .readability)
    }

    @Test func aTinyReadabilityResultYieldsToTheArticleElement() throws {
        let body = el("body", [:], el("main", [:], paragraph(Self.words(120)), paragraph(Self.words(120))))
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(paragraph("Short.")), body: body)))
        #expect(choice.source == .semantic)
    }

    @Test func schemaOrgArticleBodyMarksTheArticleWithoutAnArticleTag() throws {
        let body = el("body", [:], el("div", ["itemprop": "articleBody"], paragraph(Self.words(300))), el("div", [:], paragraph(Self.words(50, "side"))))
        let choice = try #require(ContentArbiter.choose(payload(readability: nil, body: body)))
        #expect(choice.source == .semantic)
        #expect(!choice.content.textContent.contains("side0"))
    }

    @Test func fallsBackToTheDensestContainer() throws {
        let nav = HTMLNode(tag: "div", children: (0..<30).map { el("a", ["href": "/\($0)"], .text("menu item \($0) ")) })
        let content = el("div", ["class": "x"], paragraph(Self.words(150)), paragraph(Self.words(150)), paragraph(Self.words(150)))
        let body = el("body", [:], el("div", [:], nav, content))
        let choice = try #require(ContentArbiter.choose(payload(readability: nil, body: body)))
        #expect(choice.source == .density)
        #expect(choice.content.textContent.contains("word3"))
    }

    @Test func usesJSONLDArticleBodyWhenThePageHasNoText() throws {
        let ld = #"{"@type":"NewsArticle","articleBody":"First paragraph of the story, which is reasonably long for a test.\n\nSecond paragraph of the story, also reasonably long for a test, with more words after."}"#
        let choice = try #require(ContentArbiter.choose(payload(readability: nil, body: el("body"), jsonLD: [ld])))
        #expect(choice.source == .jsonLD)
        #expect(choice.content.children.count == 2)
    }

    @Test func aHugeJSONLDBodyBeatsAPaywalledStub() throws {
        let full = Self.words(400)
        let ld = #"{"@type":"NewsArticle","articleBody":"\#(full)"}"#
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(paragraph(Self.words(60))), body: el("body"), jsonLD: [ld])))
        #expect(choice.source == .jsonLD)
    }

    @Test func fallsBackToAllParagraphsAsALastResort() throws {
        let body = el("body", [:], el("div", [:], paragraph("Short bit.")), el("span", [:], el("p", [:], .text(Self.words(30)))), el("p", [:], .text(Self.words(30, "other"))))
        let choice = try #require(ContentArbiter.choose(payload(readability: nil, body: body)))
        #expect(choice.source == .baseline)
        #expect(choice.content.children.count == 2)
    }

    @Test func returnsNilWhenThereIsNothingToRead() {
        #expect(ContentArbiter.choose(payload(readability: nil, body: el("body", [:], paragraph("Hi")))) == nil)
        #expect(ContentArbiter.choose(payload(readability: nil, body: nil)) == nil)
    }

    // MARK: - JSON-LD body

    private func ld(_ body: String) -> String {
        let escaped = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"@type\":\"NewsArticle\",\"articleBody\":\"\(escaped)\"}"
    }

    @Test func jsonLDWinsWhenTheChosenContentMissesTheArticle() throws {
        let story = Self.words(80, "story")
        let wrong = paragraph(Self.words(120, "sidebar"))
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(wrong), body: el("body"), jsonLD: [ld(story)])))
        #expect(choice.source == .jsonLD)
    }

    @Test func jsonLDDoesNotReplaceContentThatHasTheArticle() throws {
        let story = Self.words(80, "story")
        let page = paragraph(story + " " + Self.words(60, "comment"))
        let choice = try #require(ContentArbiter.choose(payload(readability: readability(page), body: el("body"), jsonLD: [ld(story)])))
        #expect(choice.source == .readability)
    }

    @Test func jsonLDEntitiesAreDecoded() throws {
        let body = "Yemen&#039;s group said &quot;no&quot; &amp; left. " + Self.words(60)
        let choice = try #require(ContentArbiter.choose(payload(readability: nil, body: el("body"), jsonLD: [ld(body)])))
        #expect(choice.content.textContent.contains("Yemen's group said \"no\" & left."))
    }

    @Test func jsonLDParagraphsFollowThePagesOwnParagraphs() throws {
        let first = "The first paragraph of the story, long enough to count as one."
        let second = "The second paragraph of the story, also long enough to count."
        var page = payload(readability: nil, body: el("body"), jsonLD: [ld(first + second + " Trailing words with no paragraph of their own, but plenty of length to keep.")])
        page.paragraphs = ["Unrelated advertisement paragraph that is not in the story at all.", first, second]
        let choice = try #require(ContentArbiter.choose(page))
        #expect(choice.content.children.map(\.textContent).prefix(2) == [first, second])
        #expect(choice.content.children.count == 3)
    }
}
