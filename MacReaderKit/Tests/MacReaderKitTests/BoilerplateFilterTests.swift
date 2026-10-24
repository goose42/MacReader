import Foundation
import Testing
@testable import MacReaderKit

struct BoilerplateFilterTests {
    private static let long = String(repeating: "A full sentence of real article text, long enough to count. ", count: 3)

    private func paragraph(_ text: String = long) -> HTMLNode { el("p", [:], .text(text)) }

    /// A distinct long paragraph, so repeats only appear where a test puts them.
    private func p(_ number: Int) -> HTMLNode { paragraph("Paragraph \(number). " + Self.long) }

    private func filter(_ children: HTMLNode..., byline: String? = nil, date: Date? = nil) -> HTMLNode {
        BoilerplateFilter.filter(HTMLNode(tag: "div", children: children), byline: byline, publishedDate: date)
    }

    private func texts(_ node: HTMLNode) -> [String] {
        node.children.map { $0.textContent.trimmingCharacters(in: .whitespaces) }
    }

    @Test func removesBlocksThatAreMostlyLinks() {
        let nav = el("div", [:], el("a", ["href": "/a"], "Politics"), " ", el("a", ["href": "/b"], "Sports"), " ", el("a", ["href": "/c"], "Weather"))
        let result = filter(paragraph(), nav, paragraph("Second paragraph " + Self.long))
        #expect(result.children.count == 2)
        #expect(!result.textContent.contains("Politics"))
    }

    @Test func keepsParagraphsThatMerelyContainLinks() {
        let text = el("p", [:], "Some context, with ", el("a", ["href": "/x"], "a link"), " in the middle, and then a good deal more words after it to finish the thought properly.")
        #expect(filter(text).children.count == 1)
    }

    @Test func removesLinkFarmLists() {
        let list = el("ul", [:], el("li", [:], el("a", ["href": "/1"], "First related story headline here")),
                      el("li", [:], el("a", ["href": "/2"], "Second related story headline here")),
                      el("li", [:], el("a", ["href": "/3"], "Third related story headline here")))
        let result = filter(paragraph(), list)
        #expect(result.children.map(\.tag) == ["p"])
    }

    @Test func keepsListsOfRealItems() {
        let list = el("ul", [:], el("li", [:], "Mix the flour and the water until smooth"), el("li", [:], "Let it rest for an hour"), el("li", [:], "Bake until golden"))
        #expect(filter(paragraph(), list).children.map(\.tag) == ["p", "ul"])
    }

    @Test func cutsEverythingAfterATerminatingHeadingNearTheEnd() {
        let result = filter(p(1), p(2), p(3), p(4), el("h3", [:], "Related articles"), paragraph("Other story teaser that is long enough to be a paragraph of its own on the page."))
        #expect(result.children.count == 4)
        #expect(!result.textContent.contains("Other story"))
    }

    @Test func aTerminatingPhraseEarlyInTheTextIsLeftAlone() {
        let result = filter(el("h2", [:], "Comments"), p(1), p(2), p(3), p(4))
        #expect(result.children.count == 5)
    }

    @Test func cutsThroughNestedContainers() {
        let tail = el("section", [:], el("h2", [:], "Leave a reply"), paragraph("Your email address will not be published, required fields are marked."))
        let result = filter(el("div", [:], p(1), p(2), p(3), p(4)), tail, paragraph("Footer text that follows the comments section on the page."))
        #expect(!result.textContent.contains("email address"))
        #expect(!result.textContent.contains("Footer text"))
    }

    @Test func dropsCopyrightLines() {
        let result = filter(p(1), el("p", [:], "© 2024 Example Times. All rights reserved."), p(2))
        #expect(result.children.count == 2)
    }

    @Test func repeatedLongParagraphsAppearOnce() {
        let result = filter(paragraph(), paragraph("Different " + Self.long), paragraph())
        #expect(result.children.count == 2)
    }

    @Test func repeatedShortLinesAreKept() {
        let result = filter(paragraph(), el("p", [:], "Yes."), paragraph("Another " + Self.long), el("p", [:], "Yes."))
        #expect(result.children.count == 4)
    }

    @Test func dropsALeadingBylineAndDateLine() {
        let date = ISO8601DateFormatter().date(from: "2024-05-01T10:00:00Z")
        let result = filter(el("p", [:], "By Ada Lovelace"), el("p", [:], "Published May 1, 2024"), paragraph(), byline: "Ada Lovelace", date: date)
        #expect(result.children.count == 1)
    }

    @Test func aBylineMentionedInTheBodyStays() {
        let result = filter(paragraph(), el("p", [:], "By Ada Lovelace"), byline: "Ada Lovelace")
        #expect(result.children.count == 2)
    }

    @Test func removesWrappersLeftEmpty() {
        let result = filter(paragraph(), el("div", [:], el("div", [:], " ")), el("section"))
        #expect(result.children.count == 1)
    }

    @Test func keepsImagesAndCaptionsWithNoText() {
        let figure = el("figure", [:], el("img", ["src": "a.png"]))
        #expect(filter(paragraph(), figure).children.map(\.tag) == ["p", "figure"])
    }
}
