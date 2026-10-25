import Foundation
import Testing
@testable import MacReaderKit

struct MOBI6MarkupTests {
    private func prepare(_ markup: String, encoding: String.Encoding = .utf8) -> String {
        MOBI6Markup.prepare(Data(markup.utf8), encoding: encoding)
    }

    private func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: Page breaks and pictures

    @Test func pageBreaksBecomeRules() {
        let html = prepare(#"<p>a</p><mbp:pagebreak/><p>b</p><MBP:PAGEBREAK /><p>c</p><mbp:pagebreak></mbp:pagebreak><p>d</p>"#)
        #expect(!html.contains("mbp:"))
        #expect(count(of: "<hr data-mr-pagebreak=\"1\">", in: html) == 3)
    }

    @Test func picturesNameTheirRecord() {
        #expect(prepare(#"<img recindex="00012" width="3">"#) == #"<img src="mobi-image:12" width="3">"#)
        #expect(prepare(#"<img align="baseline" recindex=7 />"#) == #"<img align="baseline" src="mobi-image:7" />"#)
        #expect(prepare(#"<img hirecindex="00005" lorecindex="00004" />"#) == #"<img src="mobi-image:5" lorecindex="00004" />"#)
    }

    @Test func aPictureWithBothKindsOfIndexUsesTheOrdinaryOne() {
        let html = prepare(#"<img recindex="00002" hirecindex="00009" />"#)
        #expect(html.contains("mobi-image:2"))
        #expect(!html.contains("mobi-image:9"))
    }

    @Test func elementsWrittenSelfClosingAreClosed() {
        // HTML ignores the slash on an element that isn't void, so `<a/>` would swallow everything after it.
        #expect(prepare("<p>a</p><a/><p>b</p>") == "<p>a</p><a></a><p>b</p>")
        #expect(prepare(#"<a name="x" /><b/><font size="3"/>"#) == #"<a name="x"></a><b></b><font size="3"></font>"#)
        #expect(prepare("<P>a</P><A/>") == "<P>a</P><A></A>")
    }

    @Test func voidElementsKeepTheirSlash() {
        #expect(prepare("a<br/>b<hr/><img src=\"x\"/>") == "a<br/>b<hr/><img src=\"x\"/>")
    }

    @Test func textInOtherEncodingsIsDecoded() {
        let bytes = Data("<p>Caf".utf8) + Data([0xE9]) + Data("</p>".utf8)
        #expect(MOBI6Markup.prepare(bytes, encoding: .windowsCP1252) == "<p>Café</p>")
        #expect(MOBI6Markup.prepare(bytes, encoding: .utf8).contains("Caf"))
    }

    // MARK: The contents page

    private static let filler = String(repeating: "word ", count: 80)

    /// A book whose guide points at a generated contents page at the end, with the real offsets filled in.
    private func bookWithContentsPage(prose: Bool = false) -> (data: Data, headingOffsets: [Int]) {
        let contents = prose
            ? "<p>\(Self.filler)\(Self.filler)<a filepos=@ONE@>one</a> <a filepos=@TWO@>two</a></p>"
            : #"<p><b>Table of Contents</b></p><p><a filepos=@ONE@>Chapter One</a></p><p><a filepos=@TWO@>Chapter Two</a></p>"#
        let template = """
            <html><head><guide><reference type="toc" title="Contents" filepos=@TOC@ /></guide></head><body>\
            <p align="center"><font size="7">Chapter One</font></p><p>Caf\u{E9} first text. \(Self.filler)</p>\
            <mbp:pagebreak/>\
            <p align="center"><font size="7">Chapter Two</font></p><p>Second text. \(Self.filler)</p>\
            <mbp:pagebreak/>\
            \(contents)\
            </body></html>
            """
        var zeroed = template
        for token in ["@TOC@", "@ONE@", "@TWO@"] { zeroed = zeroed.replacingOccurrences(of: token, with: "0000000000") }
        func offset(of needle: String) -> Int {
            let range = zeroed.range(of: needle)!
            return zeroed.utf8.distance(from: zeroed.startIndex, to: range.lowerBound)
        }
        let offsets = [
            offset(of: prose ? "<p>\(Self.filler)\(Self.filler)<a" : "<p><b>Table of Contents"),
            offset(of: #"<p align="center"><font size="7">Chapter One"#),
            offset(of: #"<p align="center"><font size="7">Chapter Two"#),
        ]
        var filled = zeroed
        for value in offsets {
            let range = filled.range(of: "0000000000")!
            filled.replaceSubrange(range, with: String(format: "%010d", value))
        }
        return (Data(filled.utf8), Array(offsets.dropFirst()))
    }

    @Test func theContentsPageIsDroppedAndItsTargetsAreMarkedAsHeadings() {
        let html = MOBI6Markup.prepare(bookWithContentsPage().data, encoding: .utf8)

        #expect(!html.contains("Table of Contents"))
        #expect(count(of: "data-mr-heading=\"1\"", in: html) == 2)
        #expect(html.contains(#"<p data-mr-heading="1" align="center"><font size="7">Chapter One"#))
        #expect(html.contains(#"<p data-mr-heading="1" align="center"><font size="7">Chapter Two"#))
        #expect(html.contains("Café first text."), "offsets count bytes, so a two-byte character must not shift them")
        #expect(html.hasSuffix("</body></html>"))
    }

    @Test func aGuidePointingAtProseIsLeftAlone() {
        let html = MOBI6Markup.prepare(bookWithContentsPage(prose: true).data, encoding: .utf8)
        #expect(count(of: "data-mr-heading", in: html) == 0)
        #expect(html.contains("word word word"))
        #expect(html.contains(">one</a>"))
    }

    @Test func offsetsThatAreNotTheStartOfATagAreIgnored() {
        var text = bookWithContentsPage().data
        // Point the first heading's link into the middle of its text.
        let markup = String(decoding: text, as: UTF8.self)
        let target = (markup.range(of: "Chapter One</font>").map { markup.utf8.distance(from: markup.startIndex, to: $0.lowerBound) })!
        let linkRange = markup.range(of: "<a filepos=")!
        let digits = markup.index(linkRange.upperBound, offsetBy: 10)
        text = Data(markup.replacingCharacters(in: linkRange.upperBound..<digits, with: String(format: "%010d", target)).utf8)

        let html = MOBI6Markup.prepare(text, encoding: .utf8)
        #expect(count(of: "data-mr-heading=\"1\"", in: html) == 1)
    }

    @Test func aGuideThatPointsOutsideTheTextChangesNothing() {
        let text = #"<html><head><guide><reference type="toc" filepos=9999999999 /></guide></head><body><p>Hi</p></body></html>"#
        #expect(prepare(text) == text)
    }

    @Test func aBookWithoutAGuideOnlyHasItsBreaksAndPicturesRewritten() {
        #expect(prepare("<p>Hi</p>") == "<p>Hi</p>")
    }
}
