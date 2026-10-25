import Testing
@testable import MacReaderKit

struct EbookTextTests {
    @Test func cleanCollapsesWhitespace() {
        #expect(EbookText.clean("  Moby \n  Dick\t ") == "Moby Dick")
    }

    @Test func cleanOfNothingIsNil() {
        #expect(EbookText.clean("") == nil)
        #expect(EbookText.clean(" \n\t ") == nil)
    }

    @Test func markupBecomesPlainText() {
        #expect(EbookText.plain(fromMarkup: "<p>A <b>great</b> whale.</p><p>Second&nbsp;para &amp; more.</p>") == "A great whale. Second para & more.")
        #expect(EbookText.plain(fromMarkup: "line one<br/>line two") == "line one line two")
        #expect(EbookText.plain(fromMarkup: "wo<i>rd</i>") == "word")
    }

    @Test func plainTextPassesThrough() {
        #expect(EbookText.plain(fromMarkup: "Just words.") == "Just words.")
        #expect(EbookText.plain(fromMarkup: "<p></p>") == nil)
    }
}
