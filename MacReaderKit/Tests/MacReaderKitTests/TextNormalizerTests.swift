import Testing
@testable import MacReaderKit

struct TextNormalizerTests {
    @Test func collapsesRunsOfSpaces() {
        #expect(TextNormalizer.normalize("hello    world") == "hello world")
    }

    @Test func joinsLinesBrokenMidParagraph() {
        #expect(TextNormalizer.normalize("one line\ncontinues here") == "one line continues here")
    }

    @Test func deHyphenatesWrappedWords() {
        #expect(TextNormalizer.normalize("an exam-\nple of it") == "an example of it")
    }

    @Test func keepsParagraphBreaks() {
        #expect(TextNormalizer.normalize("first para\n\nsecond para") == "first para\n\nsecond para")
    }

    @Test func dropsPageNumberOnlyLines() {
        #expect(TextNormalizer.normalize("end of page\n\n12\n\nnext page") == "end of page\n\nnext page")
    }

    @Test func trimsResult() {
        #expect(TextNormalizer.normalize("\n\n  hi  \n\n") == "hi")
    }

    @Test func keepsDigitOnlyLinesWhenAskedNotToTreatThemAsPageNumbers() {
        #expect(TextNormalizer.normalize("42", dropsPageNumbers: false) == "42")
        #expect(TextNormalizer.normalize("42") == "")
    }
}
