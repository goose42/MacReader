import Testing
@testable import MacReaderKit

struct HeadingNumberingTests {
    private typealias Block = ReaderDocument.Block

    private func heading(_ id: Int, _ text: String, level: Int = 1) -> Block {
        Block(id: id, kind: .heading(level: level), text: text)
    }

    private func paragraph(_ id: Int, _ text: String) -> Block {
        Block(id: id, kind: .paragraph, text: text)
    }

    @Test func absorbsAnEyebrowLabelIntoTheHeadingThatFollowsIt() {
        let result = HeadingNumbering.apply(to: [
            paragraph(0, "Some body text that is long enough to be a real paragraph."),
            paragraph(1, "MODULE 1"),
            heading(2, "a dozen stdlib tools"),
        ])
        #expect(result == [
            paragraph(0, "Some body text that is long enough to be a real paragraph."),
            Block(id: 1, kind: .heading(level: 1), text: "a dozen stdlib tools",
                  numbering: .init(label: "Module 1", placement: .eyebrow)),
        ])
    }

    @Test func leavesAnEyebrowShapedParagraphAloneWhenNoHeadingFollows() {
        let blocks = [paragraph(0, "Chapter 2"), paragraph(1, "Body text that carries on for a while.")]
        #expect(HeadingNumbering.apply(to: blocks) == blocks)
    }

    @Test func splitsDottedAndRomanPrefixesOffHeadingText() {
        let result = HeadingNumbering.apply(to: [
            heading(0, "2.1 Methods", level: 2),
            heading(1, "IV. Results"),
            heading(2, "3. Discussion"),
        ])
        #expect(result.map(\.text) == ["Methods", "Results", "Discussion"])
        #expect(result.map { $0.numbering?.label } == ["2.1", "IV.", "3."])
        #expect(result.allSatisfy { $0.numbering?.placement == .inline })
    }

    @Test func doesNotTreatYearsOrPlainWordsAsNumbers() {
        let blocks = [heading(0, "2025 Results"), heading(1, "A new hope"), heading(2, "Introduction")]
        #expect(HeadingNumbering.apply(to: blocks) == blocks)
    }

    @Test func doesNotNumberParagraphs() {
        let blocks = [paragraph(0, "1.2 is the ratio we measured in the experiment.")]
        #expect(HeadingNumbering.apply(to: blocks) == blocks)
    }

    @Test func keepsIDsContiguousAfterRemovingEyebrows() {
        let result = HeadingNumbering.apply(to: [
            paragraph(0, "Part I"), heading(1, "Basics"),
            paragraph(2, "Body text that carries on for a while."),
            paragraph(3, "Part II"), heading(4, "Advanced"),
        ])
        #expect(result.map(\.id) == [0, 1, 2])
    }
}
