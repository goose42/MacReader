import Foundation
import Testing
@testable import MacReaderKit

struct XHTMLParserTests {
    private func parse(_ body: String, head: String = "", htmlAttributes: String = "") throws -> XHTMLParser.Document {
        let xhtml = """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" \(htmlAttributes)>
            <head>\(head)</head>
            <body>\(body)</body>
            </html>
            """
        return try XHTMLParser.parse(Data(xhtml.utf8))
    }

    @Test func theBodyIsTheRootAndTheHeadIsLeftOut() throws {
        let document = try parse(#"<h1 class="t">Chapter</h1><p>Text</p>"#, head: "<title>My Title</title><style>p{}</style>")
        #expect(document.title == "My Title")
        #expect(document.body == el("body", [:], el("h1", ["class": "t"], "Chapter"), el("p", [:], "Text")))
    }

    @Test func languageAndDirectionComeFromTheRootElement() throws {
        #expect(try parse("<p>x</p>", htmlAttributes: #"xml:lang="fr""#).language == "fr")
        #expect(try parse("<p>x</p>", htmlAttributes: #"lang="de" dir="rtl""#).language == "de")
        #expect(try parse("<p>x</p>", htmlAttributes: #"dir="rtl""#).direction == "rtl")
        #expect(try parse("<p>x</p>").language == nil)
    }

    @Test func tagsAreLowercasedAndNamespacePrefixesDropped() throws {
        let document = try parse(#"<h:P xmlns:h="http://www.w3.org/1999/xhtml">x</h:P>"#)
        #expect(document.body.children == [el("p", [:], "x")])
    }

    @Test func keepsTheAttributesTheBuilderReadsAndDropsTheRest() throws {
        let document = try parse(#"<aside epub:type="footnote" id="n1" style="color:red" onclick="x()">Note</aside>"#)
        #expect(document.body.children == [el("aside", ["epub:type": "footnote", "id": "n1"], "Note")])
    }

    @Test func xlinkHrefBecomesHref() throws {
        let document = try parse(#"<a xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="a.xhtml#x">see</a>"#)
        #expect(document.body.children == [el("a", ["href": "a.xhtml#x"], "see")])
    }

    @Test func namedHTMLEntitiesAreUnderstood() throws {
        let document = try parse("<p>caf&eacute;&nbsp;&mdash; 1&frac12; &amp; &lt;done&gt;</p>")
        #expect(document.body.children == [el("p", [:], "café\u{A0}— 1½ & <done>")])
    }

    @Test func textAndCDATAJoinIntoOneNode() throws {
        let document = try parse("<p>one <![CDATA[<two>]]> three</p>")
        #expect(document.body.children == [el("p", [:], "one <two> three")])
    }

    @Test func anSVGCoverBecomesAnImage() throws {
        let document = try parse("""
            <div><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 600 800">\
            <image width="600" height="800" xlink:href="../images/cover.jpg"/></svg></div>
            """)
        #expect(document.body.children == [el("div", [:], el("img", ["src": "../images/cover.jpg"]))])
    }

    @Test func anSVGWithoutAPictureStaysAnSVG() throws {
        let document = try parse(#"<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>"#)
        #expect(document.body.children.map(\.tag) == ["svg"])
    }

    @Test func aDocumentWithoutABodyUsesTheRootsChildren() throws {
        let document = try XHTMLParser.parse(Data("<section><p>x</p></section>".utf8))
        #expect(document.body.children == [el("section", [:], el("p", [:], "x"))])
    }

    @Test func malformedMarkupThrows() {
        #expect(throws: XHTMLParser.Failure.self) { try parse("<p>unclosed") }
        #expect(throws: XHTMLParser.Failure.self) { try parse("<p>&unknownentity;</p>") }
        #expect(throws: XHTMLParser.Failure.self) { try XHTMLParser.parse(Data()) }
    }
}
