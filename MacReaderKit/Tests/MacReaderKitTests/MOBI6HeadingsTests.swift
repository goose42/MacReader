import Testing
@testable import MacReaderKit

struct MOBI6HeadingsTests {
    private func font(_ size: String, _ text: HTMLNode...) -> HTMLNode {
        HTMLNode(tag: "font", attributes: ["size": size], children: text)
    }

    private func promoted(_ node: HTMLNode) -> HTMLNode {
        MOBI6Headings.promote(HTMLNode(tag: "body", children: [node])).children[0]
    }

    @Test func aParagraphSetEntirelyInALargeFontIsAHeading() {
        #expect(promoted(el("p", [:], font("7", "Chapter One"))).tag == "h1")
        #expect(promoted(el("p", [:], font("6", "Chapter One"))).tag == "h2")
        #expect(promoted(el("p", [:], font("5", "Chapter One"))).tag == "h3")
    }

    @Test func aModestlyLargerOrNormalFontIsNot() {
        #expect(promoted(el("p", [:], font("4", "Subtitle"))).tag == "p")
        #expect(promoted(el("p", [:], "Plain text")).tag == "p")
        #expect(promoted(el("p", [:], font("2", "Small print"))).tag == "p")
    }

    @Test func textOutsideTheLargeFontKeepsItAParagraph() {
        // A drop cap: the first letter is large, the rest is not.
        #expect(promoted(el("p", [:], font("7", "A"), "lice was beginning to get very tired.")).tag == "p")
        #expect(promoted(el("p", [:], font("7", "Title"), " and a plain tail")).tag == "p")
    }

    @Test func longTextIsAParagraphNoMatterHowLarge() {
        let long = String(repeating: "word ", count: 40)
        #expect(promoted(el("p", [:], font("7", HTMLNode.text(long)))).tag == "p")
    }

    @Test func relativeSizesAreRelativeToNormal() {
        #expect(promoted(el("p", [:], font("+2", "Plus two"))).tag == "h3")
        #expect(promoted(el("p", [:], font("+4", "Plus four"))).tag == "h1")
        #expect(promoted(el("p", [:], font("-1", "Minus one"))).tag == "p")
    }

    @Test func nestedFontsAndInlineMarkupAreLookedThrough() {
        #expect(promoted(el("p", [:], font("7", el("b", [:], "Bold ", el("i", [:], "heading"))))).tag == "h1")
        #expect(promoted(el("p", [:], font("7", font("3", "Dropped back")))).tag == "p")
        #expect(promoted(el("p", [:], font("3", font("6", "Raised again")))).tag == "h2")
    }

    @Test func aLargeDivIsAHeadingToo() {
        #expect(promoted(el("div", [:], font("7", "Part One"))).tag == "h1")
    }

    @Test func aBlockHoldingBlocksIsNotPromoted() {
        let wrapper = promoted(el("div", [:], el("p", [:], font("7", "Inside"))))
        #expect(wrapper.tag == "div")
        #expect(wrapper.children.first?.tag == "h1")
    }

    @Test func aMarkedParagraphIsAHeadingEvenIfSetNormally() {
        #expect(promoted(el("p", ["data-mr-heading": "1"], "Appendix")).tag == "h2")
        #expect(promoted(el("p", ["data-mr-heading": "1"], font("7", "Chapter"))).tag == "h1")
    }

    @Test func aMarkedParagraphKeepsLongTextAsAHeadingToo() {
        let long = String(repeating: "word ", count: 60)
        #expect(promoted(el("p", ["data-mr-heading": "1"], HTMLNode.text(long))).tag == "h2")
    }

    @Test func existingHeadingsAreLeftAlone() {
        #expect(promoted(el("h3", [:], font("7", "Real heading"))).tag == "h3")
    }

    @Test func aHeadingKeepsItsLineBreaksSoTheBuilderReadsOneLine() {
        let paragraph = el("p", ["align": "center"], font("7", "CHAPTER I."), el("br"), font("7", " Down the Rabbit-Hole"))
        let root = MOBI6Headings.promote(HTMLNode(tag: "body", children: [paragraph, el("p", [:], "Alice was beginning.")]))
        let result = HTMLStructureBuilder.build(from: root, title: "Book", dropsRepeatedTitle: false) { _ in nil }
        #expect(result.blocks.map(\.text) == ["CHAPTER I. Down the Rabbit-Hole", "Alice was beginning."])
        #expect(result.blocks.first?.kind == .heading(level: 1))
    }
}
