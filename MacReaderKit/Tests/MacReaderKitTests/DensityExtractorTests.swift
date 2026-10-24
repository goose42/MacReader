import Foundation
import Testing
@testable import MacReaderKit

struct DensityExtractorTests {
    private func paragraph(_ text: String) -> HTMLNode { el("p", [:], .text(text)) }
    private let sentence = String(repeating: "A reasonably long sentence of article text that goes on for a while. ", count: 4)

    @Test func picksTheContainerOfDenseProseOverLinkHeavySiblings() throws {
        let menu = HTMLNode(tag: "ul", children: (0..<20).map { el("li", [:], el("a", ["href": "/\($0)"], .text("Menu entry \($0)"))) })
        let prose = el("div", ["id": "prose"], paragraph(sentence), paragraph(sentence), paragraph(sentence))
        let page = el("body", [:], el("div", [:], menu, prose))
        let best = try #require(DensityExtractor.bestNode(in: page))
        #expect(best.attributes["id"] == "prose")
    }

    @Test func returnsNilForAPageWithoutEnoughText() {
        #expect(DensityExtractor.bestNode(in: el("body", [:], paragraph("tiny"))) == nil)
    }

    @Test func textLengthCollapsesWhitespaceAndLinkLengthCountsAnchors() {
        let node = el("p", [:], "Hello   ", el("a", ["href": "/"], "big\n link"), " world")
        #expect(node.textLength == "Hello big link world".count)
        #expect(node.linkTextLength == "big link".count)
    }
}
