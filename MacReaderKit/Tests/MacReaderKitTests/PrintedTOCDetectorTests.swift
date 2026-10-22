import Testing
@testable import MacReaderKit

struct PrintedTOCDetectorTests {
    private func line(_ text: String, _ size: Double, page: Int = 0) -> TextLine {
        TextLine(text: text, fontSize: size, pageIndex: page)
    }

    /// A contents page like the real sample: small-font entries, numbers split onto their own lines, then a tagline.
    private var documentWithContents: [TextLine] {
        [
            line("CONTENTS", 8.8),
            line("Overview", 11.2),
            line("These rounds reward working code", 11.2),
            line("over cleverness", 11.2),
            line("1", 8.8),
            line("Python fluency for speed", 10.8),
            line("python 3.10+ · 7 modules", 9.6),
            line("Practical Guide", 40),
            line("Overview", 24),
            line("These rounds", 24, page: 1),
            line("reward working", 24, page: 1),
            line("code over cleverness", 24, page: 1),
            line("Body text goes on and on here.", 13.6, page: 1),
            line("Python fluency", 24, page: 2),
            line("for speed", 24, page: 2),
            line("More body text for the section.", 13.6, page: 2),
        ]
    }

    @Test func stripsTheContentsBlockIncludingSplitNumberedEntries() {
        let result = PrintedTOCDetector.strip(documentWithContents, bodySize: 13.6)
        #expect(result.map(\.text).prefix(2) == ["python 3.10+ · 7 modules", "Practical Guide"])
        #expect(!result.map(\.text).contains("CONTENTS"))
        #expect(result.count == documentWithContents.count - 6)
    }

    @Test func keepsATaglineThatFollowsTheContents() {
        let result = PrintedTOCDetector.strip(documentWithContents, bodySize: 13.6)
        #expect(result.map(\.text).contains("python 3.10+ · 7 modules"))
    }

    @Test func doesNothingWithoutAContentsLine() {
        let lines = [line("Intro", 24), line("Body.", 13.6)]
        #expect(PrintedTOCDetector.strip(lines, bodySize: 13.6) == lines)
    }

    @Test func doesNothingWhenNothingAfterContentsEchoesTheDocument() {
        let lines = [line("Contents", 11), line("Totally unrelated words", 9), line("Body.", 13.6)]
        #expect(PrintedTOCDetector.strip(lines, bodySize: 13.6) == lines)
    }

    @Test func ignoresAContentsWordDeepInTheDocument() {
        let lines = [line("Body.", 13.6), line("Contents", 9, page: 9), line("Body.", 13.6, page: 9)]
        #expect(PrintedTOCDetector.strip(lines, bodySize: 13.6) == lines)
    }
}
