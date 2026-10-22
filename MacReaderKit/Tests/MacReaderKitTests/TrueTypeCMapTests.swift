import Foundation
import Testing
@testable import MacReaderKit

struct TrueTypeCMapTests {
    @Test func readsTheMacintoshCodeToGlyphTable() {
        let codes = TrueTypeCMap.glyphs(in: LigatureFontFixture.jetBrainsMonoSubset)
        #expect(codes[0x21] == 12)
        #expect(codes[0x22] == 8)
        #expect(codes.keys.sorted() == Array(0x21...0x2b))
    }

    @Test func returnsNothingForDataThatIsNotAFont() {
        #expect(TrueTypeCMap.glyphs(in: Data([1, 2, 3])).isEmpty)
    }
}
