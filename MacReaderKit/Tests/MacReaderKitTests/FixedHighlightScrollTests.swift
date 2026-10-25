import Testing
@testable import MacReaderKit

struct FixedHighlightScrollTests {
    private func offset(
        sentenceTop: Double, lines: Int = 3, currentOffset: Double = 1000,
        viewportHeight: Double = 600, contentHeight: Double = 5000
    ) -> Double {
        FixedHighlightScroll.targetOffset(
            sentenceTop: sentenceTop, lineHeight: 30, lines: lines, currentOffset: currentOffset,
            viewportHeight: viewportHeight, contentHeight: contentHeight)
    }

    @Test func putsTheSentenceTheChosenNumberOfLinesBelowTheTop() {
        // Sentence is 400pt below the top of the viewport; it should end up 3 × 30pt below it.
        #expect(offset(sentenceTop: 400) == 1000 + 400 - 90)
    }

    @Test func aSentenceAlreadyInPlaceDoesNotMoveThePage() {
        #expect(offset(sentenceTop: 90) == 1000)
    }

    @Test func doesNotScrollBeforeTheStartOfThePage() {
        #expect(offset(sentenceTop: 10, currentOffset: 20) == 0)
    }

    @Test func doesNotScrollPastTheEndOfThePage() {
        #expect(offset(sentenceTop: 500, currentOffset: 4300) == 4400)
    }

    @Test func aPageShorterThanTheViewportStaysAtTheTop() {
        #expect(offset(sentenceTop: 300, currentOffset: 0, viewportHeight: 600, contentHeight: 400) == 0)
    }

    @Test func linesAreLimitedToOneThroughTen() {
        #expect(offset(sentenceTop: 400, lines: 0) == 1000 + 400 - 30)
        #expect(offset(sentenceTop: 400, lines: 99) == 1000 + 400 - 300)
    }
}
