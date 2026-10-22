import Testing
@testable import MacReaderKit

struct FontStatisticsTests {
    @Test func bodySizeIsTheSizeWithTheMostCharacters() {
        let lines = [
            TextLine(text: "Big title", fontSize: 40, pageIndex: 0),
            TextLine(text: "a long body line with many characters", fontSize: 12, pageIndex: 0),
            TextLine(text: "another long body line with many", fontSize: 12, pageIndex: 1),
            TextLine(text: "small", fontSize: 9, pageIndex: 1),
        ]
        #expect(FontStatistics.bodySize(of: lines) == 12)
    }

    @Test func bodySizeOfNothingIsZero() {
        #expect(FontStatistics.bodySize(of: []) == 0)
    }
}
