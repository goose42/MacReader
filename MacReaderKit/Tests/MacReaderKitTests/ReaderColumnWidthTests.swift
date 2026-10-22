import Testing
@testable import MacReaderKit

struct ReaderColumnWidthTests {
    @Test func rawValuesAreStableBecauseTheyArePersisted() {
        #expect(ReaderColumnWidth.narrow.rawValue == "narrow")
        #expect(ReaderColumnWidth.wide.rawValue == "wide")
    }

    @Test func narrowCapsTheColumnAndWideDoesNot() {
        #expect(ReaderColumnWidth.narrow.maxWidth == 680)
        #expect(ReaderColumnWidth.wide.maxWidth == nil)
    }

    @Test func wideHasWiderSideMargins() {
        #expect(ReaderColumnWidth.wide.horizontalPadding > ReaderColumnWidth.narrow.horizontalPadding)
    }
}
