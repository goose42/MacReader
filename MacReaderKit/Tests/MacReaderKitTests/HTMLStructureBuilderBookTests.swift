import AppKit
import Foundation
import Testing
@testable import MacReaderKit

/// How the builder reads what books add to web markup: `epub:type` notes, page breaks and chapter sections.
struct HTMLStructureBuilderBookTests {
    private func build(_ nodes: HTMLNode..., title: String = "Title") -> [String] {
        summary(HTMLStructureBuilder.build(from: HTMLNode(tag: "body", children: nodes), title: title, dropsRepeatedTitle: false) { _ in nil })
    }

    private func summary(_ result: HTMLStructureBuilder.Result) -> [String] {
        result.blocks.map { block in
            switch block.kind {
            case .heading(let level): "h\(level): \(block.text)"
            case .paragraph: "p: \(block.text)"
            case .callout: "callout: \(block.text)"
            case .image: "image"
            case .footnote(let marker): "footnote \(marker): \(block.text)"
            default: "other: \(block.text)"
            }
        }
    }

    private func chapter(_ title: String, _ children: HTMLNode...) -> HTMLNode {
        HTMLNode(tag: "section", attributes: ["data-mr-chapter": title], children: children)
    }

    // MARK: Notes

    @Test func anAsideTypedAsAFootnoteIsAFootnoteMovedToTheEnd() {
        let note = el("aside", ["epub:type": "footnote", "id": "n1"], el("p", [:], el("a", ["href": "#r1"], "1"), " The note."))
        #expect(build(el("p", [:], "Body text."), note, el("p", [:], "More body text."))
            == ["p: Body text.", "p: More body text.", "footnote 1: The note."])
    }

    @Test func aNumberFollowedByPunctuationIsTheMarker() {
        let notes = [
            el("aside", ["epub:type": "footnote"], el("p", [:], "2. Second.")),
            el("aside", ["epub:type": "endnote"], el("p", [:], "[3] Third.")),
            el("aside", ["epub:type": "footnote"], el("p", [:], el("sup", [:], "*"), " Starred.")),
        ]
        #expect(build(notes[0], notes[1], notes[2]) == ["footnote 2: Second.", "footnote 3: Third.", "footnote *: Starred."])
    }

    @Test func aNoteWithoutAMarkerIsNumberedInOrder() {
        let first = el("aside", ["epub:type": "footnote"], el("p", [:], "1984 was the year."))
        let second = el("aside", ["role": "doc-footnote"], el("p", [:], "Just a note."))
        #expect(build(first, second) == ["footnote 1: 1984 was the year.", "footnote 2: Just a note."])
    }

    @Test func plainAsidesAreStillCallouts() {
        #expect(build(el("aside", [:], el("p", [:], "Heads up"))) == ["callout: Heads up"])
        #expect(build(el("aside", ["epub:type": "sidebar"], el("p", [:], "Aside"))) == ["callout: Aside"])
    }

    @Test func notesStayWithTheirChapter() {
        let note = el("aside", ["epub:type": "footnote"], el("p", [:], "1. Note one."))
        #expect(build(
            chapter("One", el("h1", [:], "One"), el("p", [:], "First."), note, el("p", [:], "Still one.")),
            chapter("Two", el("h1", [:], "Two"), el("p", [:], "Second.")))
            == ["h1: One", "p: First.", "p: Still one.", "footnote 1: Note one.", "h1: Two", "p: Second."])
    }

    @Test func aContainerOfNotesTypedByEPUBYieldsFootnotes() {
        let container = el("section", ["epub:type": "footnotes"],
            el("aside", ["epub:type": "footnote"], el("p", [:], "1. One.")),
            el("aside", ["epub:type": "footnote"], el("p", [:], "2. Two.")))
        #expect(build(el("p", [:], "Text."), container) == ["p: Text.", "footnote 1: One.", "footnote 2: Two."])
    }

    // MARK: Page breaks

    @Test func pageNumbersAreLeftOutOfTheText() {
        let inline = el("p", [:], "Before ", el("span", ["epub:type": "pagebreak", "id": "p5"], "5"), "after.")
        let block = el("div", ["role": "doc-pagebreak"], "6")
        #expect(build(inline, block, el("p", [:], "Next.")) == ["p: Before after.", "p: Next."])
    }

    // MARK: Chapters

    @Test func aChapterWithoutAHeadingGetsItsTitle() {
        #expect(build(chapter("Prologue", el("p", [:], "Once.")), chapter("One", el("h2", [:], "One"), el("p", [:], "Then.")))
            == ["h1: Prologue", "p: Once.", "h1: One", "p: Then."])
    }

    @Test func aChapterThatOpensWithAHeadingKeepsOnlyThat() {
        #expect(build(chapter("Part", el("h1", [:], "Part One"), el("p", [:], "Text."))) == ["h1: Part One", "p: Text."])
    }

    @Test func aPictureBeforeTheHeadingDoesNotCountAsOpeningTheChapter() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let picture = try #require(rep.representation(using: .png, properties: [:]))
        let root = HTMLNode(tag: "body", children: [chapter("One", el("img", ["src": "o.png"]), el("h1", [:], "One"), el("p", [:], "Text."))])
        let result = HTMLStructureBuilder.build(from: root, title: "Book", dropsRepeatedTitle: false) { $0 == "o.png" ? picture : nil }
        #expect(summary(result) == ["image", "h1: One", "p: Text."])
    }

    @Test func blockIDsStaySequentialWhenATitleIsInserted() {
        let result = HTMLStructureBuilder.build(
            from: HTMLNode(tag: "body", children: [chapter("A", el("p", [:], "x")), chapter("B", el("p", [:], "y"))]),
            title: "Book", dropsRepeatedTitle: false) { _ in nil }
        #expect(result.blocks.map(\.id) == [0, 1, 2, 3])
    }

    // MARK: Options

    @Test func theBookTitleIsKeptWhenAHeadingRepeatsIt() {
        let root = HTMLNode(tag: "body", children: [el("h1", [:], "Moby Dick"), el("p", [:], "Call me Ishmael.")])
        let kept = HTMLStructureBuilder.build(from: root, title: "Moby Dick", dropsRepeatedTitle: false) { _ in nil }
        let dropped = HTMLStructureBuilder.build(from: root, title: "Moby Dick") { _ in nil }
        #expect(summary(kept) == ["h1: Moby Dick", "p: Call me Ishmael."])
        #expect(summary(dropped) == ["p: Call me Ishmael."])
    }

    @Test func imagesAreNamedAfterTheirSource() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let picture = try #require(rep.representation(using: .png, properties: [:]))
        let root = HTMLNode(tag: "body", children: [el("img", ["src": "a.png"])])
        let result = HTMLStructureBuilder.build(from: root, title: "Book", imagePrefix: "book") { _ in picture }
        #expect(result.images.keys.sorted() == ["book-1.png"])
        #expect(result.blocks.first?.kind == .image(name: "book-1.png", aspectRatio: 2))
    }
}
