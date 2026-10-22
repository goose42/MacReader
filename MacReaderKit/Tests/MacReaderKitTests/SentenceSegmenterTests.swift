import Foundation
import Testing
@testable import MacReaderKit

struct SentenceSegmenterTests {
    private func sentences(_ text: String) -> [String] {
        let ns = text as NSString
        return SentenceSegmenter.ranges(in: text).map { ns.substring(with: NSRange($0.lowerBound..<$0.upperBound)) }
    }

    @Test func splitsOnPeriodsQuestionMarksAndExclamations() {
        #expect(sentences("It works. Does it? Yes!") == ["It works.", "Does it?", "Yes!"])
    }

    @Test func doesNotSplitAfterIe() {
        #expect(sentences("Use a tool, i.e. a hammer, for this. Then stop.") == ["Use a tool, i.e. a hammer, for this.", "Then stop."])
    }

    @Test func doesNotSplitAfterEg() {
        #expect(sentences("Pick one, e.g. the red one. Done.") == ["Pick one, e.g. the red one.", "Done."])
    }

    @Test func doesNotSplitAfterTitles() {
        #expect(sentences("We met Dr. Smith today. He left.") == ["We met Dr. Smith today.", "He left."])
    }

    @Test func doesNotSplitInsideDottedAcronyms() {
        #expect(sentences("The U.S. Army arrived. It stayed.") == ["The U.S. Army arrived.", "It stayed."])
    }

    @Test func doesNotSplitAfterInitials() {
        #expect(sentences("J. R. R. Tolkien wrote it. Many read it.") == ["J. R. R. Tolkien wrote it.", "Many read it."])
    }

    @Test func doesNotSplitInsideDecimals() {
        #expect(sentences("It grew 3.5 percent. Then it fell.") == ["It grew 3.5 percent.", "Then it fell."])
    }

    @Test func keepsEllipsisInsideASentence() {
        #expect(sentences("Wait... what? Fine.") == ["Wait... what?", "Fine."])
    }

    @Test func keepsClosingQuotesWithTheirSentence() {
        #expect(sentences("He said “Stop.” Then he left.") == ["He said “Stop.”", "Then he left."])
    }

    @Test func keepsParentheticalReferencesTogether() {
        #expect(sentences("It is known (see Fig. 2). Next point.") == ["It is known (see Fig. 2).", "Next point."])
    }

    @Test func etcSplitsBeforeACapitalButNotBeforeALowercaseWord() {
        #expect(sentences("Bring pens, etc. The rest stays.") == ["Bring pens, etc.", "The rest stays."])
        #expect(sentences("Bring pens, etc. and paper. Go.") == ["Bring pens, etc. and paper.", "Go."])
    }

    @Test func aTrailingFragmentWithoutPunctuationIsASentence() {
        #expect(sentences("One. Two") == ["One.", "Two"])
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(sentences("  One.   Two.  ") == ["One.", "Two."])
    }

    @Test func emptyOrBlankTextHasNoSentences() {
        #expect(sentences("") == [])
        #expect(sentences("   ") == [])
    }

    @Test func rangesAreUTF16OffsetsIntoTheText() {
        #expect(SentenceSegmenter.ranges(in: "Hi. Yo.") == [0..<3, 4..<7])
    }
}
