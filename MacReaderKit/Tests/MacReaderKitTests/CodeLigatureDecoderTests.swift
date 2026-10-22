import Foundation
import Testing
@testable import MacReaderKit

struct CodeLigatureDecoderTests {
    private let expected = [
        "!\"": "__", "!#": "<=", "!$": "/>", "!!%": "-->", "!!&": "...",
        "!'": "--", "!(": "->", "!)": ":=", "!*": ">=", "!+": "==",
    ]

    @Test func namesEachLigatureGlyphInAnEmbeddedSubsetFromItsOutline() {
        #expect(CodeLigatureDecoder.replacements(forFont: LigatureFontFixture.jetBrainsMonoSubset) == expected)
    }

    @Test func rewritesGarbledRunsAndLeavesOtherTextAlone() {
        let line = "def !\"init!\"(self): L1 !!% L2 and then Wow! done"
        #expect(CodeLigatureDecoder.apply(expected, to: line) == "def __init__(self): L1 --> L2 and then Wow! done")
    }

    @Test func prefersTheLongestRunAtEachPosition() {
        #expect(CodeLigatureDecoder.apply(expected, to: "a !!% b") == "a --> b")
        #expect(CodeLigatureDecoder.apply(expected, to: "x !!& y") == "x ... y")
    }

    @Test func ignoresFontsWithoutASpacerGlyph() {
        #expect(CodeLigatureDecoder.replacements(forFont: Data([0, 1, 0, 0])).isEmpty)
    }
}
