import Foundation
import Testing
@testable import MacReaderKit

struct CosmeticFilterParserTests {
    private func parse(_ lines: String...) -> CosmeticFilters {
        CosmeticFilterParser.parse(lists: [lines.joined(separator: "\n")])
    }

    @Test func plainClassAndIDRulesAreIndexedByName() {
        let filters = parse("##.popup-banner", "###newsletter_box")
        #expect(filters.classes == ["popup-banner"])
        #expect(filters.ids == ["newsletter_box"])
    }

    @Test func commentsHeadersAndBlankLinesAreIgnored() {
        let filters = parse("[Adblock Plus 2.0]", "! Title: Annoyances", "", "##.keep")
        #expect(filters.classes == ["keep"])
    }

    @Test func siteSpecificRulesAreDropped() {
        #expect(parse("example.com##.promo", "a.com,b.com###box").classes.isEmpty)
    }

    @Test func exceptionsAndOtherRuleTypesAreDropped() {
        let filters = parse("#@#.allowed", "example.com#@#.x", "#?#.proc", "#$#.style", "##+js(abort)", "||ads.example.com^")
        #expect(filters.classes.isEmpty && filters.ids.isEmpty && filters.complex.isEmpty)
    }

    @Test func proceduralSelectorsAreDropped() {
        let filters = parse("##.a:has-text(Sponsored)", "##div:xpath(//p)", "##.b:upward(2)", "##.c:style(color:red)", "##.d:-abp-has(x)", "##.e:matches-css(display:none)")
        #expect(filters.classes.isEmpty && filters.complex.isEmpty)
    }

    @Test func compoundSelectorsAreKeyedByTheirFirstClassOrID() {
        let filters = parse("##div.ad-wrapper > a.link", "##.sidebar .promo-card", "##section#top-bar.sticky")
        #expect(filters.complex[".ad-wrapper"] == ["div.ad-wrapper > a.link"])
        #expect(filters.complex[".sidebar"] == [".sidebar .promo-card"])
        #expect(filters.complex["#top-bar"] == ["section#top-bar.sticky"])
    }

    @Test func selectorsWithoutAClassOrIDAreTooBroadAndDropped() {
        #expect(parse("##a[href^=\"https://ads.example.com\"]", "##iframe[src*=\"banner\"]", "##ins").complex.isEmpty)
    }

    @Test func listsOfSelectorsAreSkipped() {
        #expect(parse("##.a, .b").classes.isEmpty)
    }

    @Test func pseudoElementsAndOverlongSelectorsAreSkipped() {
        let long = "##.x " + String(repeating: ".y ", count: 200) + "z"
        let filters = parse("##.p::before", long)
        #expect(filters.classes.isEmpty && filters.complex.isEmpty)
    }

    @Test func mergesSeveralListsWithoutDuplicates() {
        let filters = CosmeticFilterParser.parse(lists: ["##.a\n##.b", "##.b\n###c"])
        #expect(filters.classes == ["a", "b"])
        #expect(filters.ids == ["c"])
    }

    @Test func encodesToJSONTheScriptsCanRead() throws {
        let filters = parse("##.a", "###b", "##.c .d")
        let json = try JSONSerialization.jsonObject(with: filters.json) as? [String: Any]
        #expect(json?["classes"] as? [String] == ["a"])
        #expect(json?["ids"] as? [String] == ["b"])
        #expect((json?["complex"] as? [String: [String]])?[".c"] == [".c .d"])
    }
}
