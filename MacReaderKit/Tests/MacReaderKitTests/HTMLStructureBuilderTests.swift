import AppKit
import Foundation
import Testing
@testable import MacReaderKit

extension HTMLNode: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
}

private func el(_ tag: String, _ attributes: [String: String] = [:], _ children: HTMLNode...) -> HTMLNode {
    HTMLNode(tag: tag, attributes: attributes, children: children)
}

private func png(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

struct HTMLStructureBuilderTests {
    private func build(_ nodes: HTMLNode..., title: String = "Title", images: [String: Data] = [:]) -> HTMLStructureBuilder.Result {
        HTMLStructureBuilder.build(from: HTMLNode(tag: "div", children: nodes), title: title) { images[$0] }
    }

    /// One short line per block, so a test reads as the document it expects.
    private func summary(_ result: HTMLStructureBuilder.Result) -> [String] {
        result.blocks.map { block in
            switch block.kind {
            case .heading(let level): "h\(level): \(block.text)"
            case .paragraph: "p: \(block.text)"
            case .listItem(let marker, let depth): "li\(depth) \(marker): \(block.text)"
            case .quote: "quote: \(block.text)"
            case .code: "code: \(block.text)"
            case .callout: "callout: \(block.text)"
            case .caption: "caption: \(block.text)"
            case .image: "image"
            case .table(let table): "table\(table.hasHeader ? "*" : ""): \(table.rows.map { $0.joined(separator: "|") }.joined(separator: " / "))"
            case .footnote(let marker): "footnote \(marker): \(block.text)"
            }
        }
    }

    // MARK: - Text

    @Test func headingsAndParagraphsKeepTheirOrder() {
        let result = build(el("h2", [:], "Intro"), el("p", [:], "First."), el("h3", [:], "Detail"), el("p", [:], "Second."))
        #expect(summary(result) == ["h1: Intro", "p: First.", "h2: Detail", "p: Second."])
    }

    @Test func whitespaceCollapsesAndInlineMarkupDisappears() {
        let result = build(el("p", [:], "  A   very\n  ", el("strong", [:], "bold"), " and ", el("a", ["href": "/x"], "linked"), "\u{A0}word. "))
        #expect(summary(result) == ["p: A very bold and linked word."])
    }

    @Test func aDivOfInlineContentIsAParagraph() {
        let result = build(el("div", [:], "Loose text with ", el("em", [:], "emphasis"), "."))
        #expect(summary(result) == ["p: Loose text with emphasis."])
    }

    @Test func blockChildrenSplitTheInlineRunsAroundThem() {
        let result = build(el("div", [:], "Before", el("p", [:], "Inside"), "After"))
        #expect(summary(result) == ["p: Before", "p: Inside", "p: After"])
    }

    @Test func twoLineBreaksSplitAParagraphButOneIsASpace() {
        let result = build(el("p", [:], "One", el("br"), "line", el("br"), el("br"), "Two"))
        #expect(summary(result) == ["p: One line", "p: Two"])
    }

    @Test func scriptsStylesAndFormsAreIgnored() {
        let result = build(el("p", [:], "Keep"), el("script", [:], "alert(1)"), el("style", [:], "p{}"), el("form", [:], el("p", [:], "Subscribe")), el("nav", [:], el("p", [:], "Menu")))
        #expect(summary(result) == ["p: Keep"])
    }

    @Test func permalinkAnchorsInHeadingsAreDropped() {
        let result = build(el("h2", [:], "Setup", el("a", ["href": "#setup", "class": "anchor"], "#")))
        #expect(summary(result) == ["h1: Setup"])
    }

    @Test func mathPrefersItsTeXAnnotation() {
        let math = el("math", ["alttext": "x squared"], el("semantics", [:], el("mi", [:], "x"), el("annotation", ["encoding": "application/x-tex"], "x^2")))
        #expect(summary(build(el("p", [:], "Let ", math, " be."))) == ["p: Let x^2 be."])
    }

    // MARK: - Lists, quotes, code, callouts

    @Test func listsBecomeMarkedItemsAndNestedItemsIndent() {
        let result = build(
            el("ul", [:], el("li", [:], "Apples", el("ul", [:], el("li", [:], "Fuji"))), el("li", [:], "Pears")),
            el("ol", ["start": "3"], el("li", [:], "Third"), el("li", [:], "Fourth")))
        #expect(summary(result) == ["li0 •: Apples", "li1 ◦: Fuji", "li0 •: Pears", "li0 3.: Third", "li0 4.: Fourth"])
    }

    @Test func listItemsWithParagraphsJoinThemIntoOneItem() {
        let result = build(el("ul", [:], el("li", [:], el("p", [:], "One"), el("p", [:], "Two"))))
        #expect(summary(result) == ["li0 •: One Two"])
    }

    @Test func blockquotesBecomeQuotes() {
        let result = build(el("blockquote", [:], el("p", [:], "First."), el("p", [:], "Second.")))
        #expect(summary(result) == ["quote: First.", "quote: Second."])
    }

    @Test func preKeepsItsLineBreaksAndIndentation() {
        let result = build(el("pre", [:], el("code", [:], "\nfunc f() {\n    return 1\n}\n")))
        #expect(summary(result) == ["code: func f() {\n    return 1\n}"])
    }

    @Test func monospacedBlocksThatKeepWhitespaceAreCode() {
        let result = build(el("div", ["data-mr-mono": "1", "data-mr-pre": "1"], "a  b\nc"), el("div", ["data-mr-mono": "1"], "Just a monospaced paragraph."))
        #expect(summary(result) == ["code: a  b\nc", "p: Just a monospaced paragraph."])
    }

    @Test func asidesDetailsAndAdmonitionsAreCallouts() {
        let result = build(
            el("aside", [:], el("p", [:], "Heads"), el("p", [:], "up")),
            el("details", [:], el("summary", [:], "More"), el("p", [:], "Hidden detail")),
            el("div", ["class": "markdown-alert warning"], el("p", [:], "Careful")))
        #expect(summary(result) == ["callout: Heads up", "callout: More Hidden detail", "callout: Careful"])
    }

    @Test func theFilterSMarkedAsidesAreCallouts() {
        let result = build(el("p", [:], "Before"), el("mr-callout", [:], el("p", [:], "A note.")), el("p", [:], "After"))
        #expect(summary(result) == ["p: Before", "callout: A note.", "p: After"])
    }

    @Test func definitionListsReadAsParagraphs() {
        let result = build(el("dl", [:], el("dt", [:], "Term"), el("dd", [:], "Meaning")))
        #expect(summary(result) == ["p: Term", "p: Meaning"])
    }

    // MARK: - Tables

    @Test func aTableWithHeadersIsADataTable() {
        let table = el("table", [:],
            el("thead", [:], el("tr", [:], el("th", [:], "Name"), el("th", [:], "Qty"))),
            el("tbody", [:], el("tr", [:], el("td", [:], "Bolt"), el("td", [:], "4")), el("tr", [:], el("td", [:], "Nut"), el("td", [:], "9"))))
        #expect(summary(build(table)) == ["table*: Name|Qty / Bolt|4 / Nut|9"])
    }

    @Test func spansPadTheGrid() {
        let table = el("table", [:],
            el("tr", [:], el("th", ["colspan": "2"], "Both"), el("th", [:], "C")),
            el("tr", [:], el("td", ["rowspan": "2"], "A"), el("td", [:], "B"), el("td", [:], "C")),
            el("tr", [:], el("td", [:], "D"), el("td", [:], "E")))
        #expect(summary(build(table)) == ["table*: Both||C / A|B|C / |D|E"])
    }

    @Test func aLayoutTableIsUnwrappedIntoItsCellContent() {
        let layout = el("table", ["role": "presentation"], el("tr", [:], el("td", [:], el("p", [:], "Left")), el("td", [:], el("p", [:], "Right"))))
        #expect(summary(build(layout)) == ["p: Left", "p: Right"])
    }

    @Test func aSmallHeaderlessTableIsLayout() {
        let small = el("table", [:], el("tr", [:], el("td", [:], "a"), el("td", [:], "b")))
        #expect(summary(build(small)) == ["p: a", "p: b"])
    }

    @Test func aCaptionedTableKeepsItsCaptionAfterIt() {
        let table = el("table", [:], el("caption", [:], "Sales"),
            el("tr", [:], el("th", [:], "A"), el("th", [:], "B")), el("tr", [:], el("td", [:], "1"), el("td", [:], "2")))
        #expect(summary(build(table)) == ["table*: A|B / 1|2", "caption: Sales"])
    }

    // MARK: - Images

    @Test func figuresBecomeAnImageAndItsCaption() {
        let figure = el("figure", [:], el("img", ["src": "a.png", "alt": "A"]), el("figcaption", [:], "Look at this."))
        let result = build(figure, images: ["a.png": png(width: 200, height: 100)])
        #expect(summary(result) == ["image", "caption: Look at this."])
        guard case .image(let name, let aspect) = result.blocks[0].kind else { Issue.record("not an image"); return }
        #expect(aspect == 2)
        #expect(result.images[name] != nil)
    }

    @Test func tinyImagesAreDropped() {
        let result = build(el("img", ["src": "pixel.png"]), el("p", [:], "Text"), images: ["pixel.png": png(width: 1, height: 1)])
        #expect(summary(result) == ["p: Text"])
    }

    @Test func imagesThatCouldNotBeLoadedAreDropped() {
        #expect(summary(build(el("img", ["src": "https://example.com/remote.jpg"]), el("p", [:], "Text"))) == ["p: Text"])
    }

    @Test func srcsetPicksTheLargestCandidate() {
        let img = el("img", ["src": "small.png", "srcset": "small.png 480w, large.png 1600w, medium.png 800w"])
        let result = build(img, images: ["small.png": png(width: 48, height: 48), "large.png": png(width: 160, height: 80), "medium.png": png(width: 80, height: 40)])
        guard case .image(_, let aspect) = result.blocks.first?.kind else { Issue.record("not an image"); return }
        #expect(aspect == 2)
    }

    @Test func pictureSourcesAreConsidered() {
        let picture = el("picture", [:], el("source", ["srcset": "wide.png 2x, wide-1x.png"]), el("img", ["src": "fallback.png"]))
        let result = build(picture, images: ["wide.png": png(width: 120, height: 40), "wide-1x.png": png(width: 60, height: 20), "fallback.png": png(width: 40, height: 40)])
        guard case .image(_, let aspect) = result.blocks.first?.kind else { Issue.record("not an image"); return }
        #expect(aspect == 3)
    }

    @Test func lazyLoadedImagesUseTheirDataAttributes() {
        let img = el("img", ["src": "placeholder.gif", "data-src": "real.png"])
        let result = build(img, images: ["placeholder.gif": png(width: 1, height: 1), "real.png": png(width: 90, height: 60)])
        #expect(summary(result) == ["image"])
    }

    // MARK: - Footnotes

    @Test func wikipediaStyleReferencesBecomeFootnotesAndMarkersLeaveTheText() {
        let reference = el("sup", ["class": "reference", "id": "cite_ref-1"], el("a", ["href": "#cite_note-1"], "[1]"))
        let notes = el("ol", ["class": "references"],
            el("li", ["id": "cite_note-1"], el("span", ["class": "mw-cite-backlink"], el("a", ["href": "#cite_ref-1"], "^")), " ", el("span", ["class": "reference-text"], "A source.")))
        #expect(summary(build(el("p", [:], "A claim.", reference), notes)) == ["p: A claim.", "footnote 1: A source."])
    }

    @Test func markdownItFootnotesDropTheirBacklinks() {
        let reference = el("sup", ["class": "footnote-ref"], el("a", ["href": "#fn1", "id": "fnref1"], "[1]"))
        let notes = el("section", ["class": "footnotes"], el("ol", ["class": "footnotes-list"],
            el("li", ["id": "fn1", "class": "footnote-item"], el("p", [:], "The note. ", el("a", ["href": "#fnref1", "class": "footnote-backref"], "↩︎")))))
        #expect(summary(build(el("p", [:], "Claim", reference, "."), notes)) == ["p: Claim.", "footnote 1: The note."])
    }

    @Test func accessibilityRolesMarkNotesToo() {
        let reference = el("a", ["href": "#n1", "role": "doc-noteref"], "1")
        let notes = el("div", ["role": "doc-endnotes"], el("ol", [:], el("li", ["id": "n1", "role": "doc-footnote"], "Explained ", el("a", ["role": "doc-backlink", "href": "#r"], "↩"))))
        #expect(summary(build(el("p", [:], "Text", reference), notes)) == ["p: Text", "footnote 1: Explained"])
    }

    @Test func substackFootnotesUseTheirOwnNumber() {
        let notes = el("div", ["class": "footnote"], el("a", ["class": "footnote-number"], "2"), el("div", ["class": "footnote-content"], el("p", [:], "Substack note.")))
        #expect(summary(build(el("p", [:], "Body."), notes)) == ["p: Body.", "footnote 2: Substack note."])
    }

    // MARK: - Headings

    @Test func aHeadingRepeatingTheTitleIsDropped() {
        let result = build(el("h1", [:], "My Great Article"), el("p", [:], "Text."), el("h2", [:], "Part"), title: "My Great Article")
        #expect(summary(result) == ["p: Text.", "h1: Part"])
    }

    @Test func headingLevelsCloseUpTheirGaps() {
        let result = build(el("h2", [:], "A"), el("h4", [:], "B"), el("h4", [:], "C"), el("h2", [:], "D"), el("h6", [:], "E"))
        #expect(summary(result) == ["h1: A", "h2: B", "h2: C", "h1: D", "h3: E"])
    }

    @Test func leadingSectionNumbersMoveIntoNumbering() {
        let result = build(el("h2", [:], "2.1 Methods"))
        #expect(result.blocks.first?.numbering?.label == "2.1")
        #expect(result.blocks.first?.text == "Methods")
    }

    @Test func blockIDsAreSequential() {
        let result = build(el("p", [:], "A"), el("p", [:], "B"), el("p", [:], "C"))
        #expect(result.blocks.map(\.id) == [0, 1, 2])
    }
}
