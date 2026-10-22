import Testing
@testable import MacReaderKit

struct SentenceNavigatorTests {
    private typealias Position = SentenceNavigator.Position

    private let document = ReaderDocument(title: "Doc", blocks: [
        .init(id: 0, kind: .heading(level: 1), text: "Intro"),
        .init(id: 1, kind: .paragraph, text: "One. Two."),
        .init(id: 2, kind: .footnote(marker: "1"), text: "A note."),
        .init(id: 3, kind: .paragraph, text: "Three."),
    ])

    @Test func startsOnTheFirstSentence() {
        let navigator = SentenceNavigator(document: document)
        #expect(navigator.current == Position(blockID: 0, sentence: 0))
        #expect(navigator.currentRange == 0..<5)
    }

    @Test func nextWalksSentencesAcrossBlocksAndSkipsFootnotes() {
        var navigator = SentenceNavigator(document: document)
        var visited = [navigator.current]
        while navigator.next() { visited.append(navigator.current) }
        #expect(visited == [
            Position(blockID: 0, sentence: 0), Position(blockID: 1, sentence: 0),
            Position(blockID: 1, sentence: 1), Position(blockID: 3, sentence: 0),
        ])
    }

    @Test func nextStopsAtTheEndWithoutWrapping() {
        var navigator = SentenceNavigator(document: document)
        while navigator.next() {}
        #expect(navigator.next() == false)
        #expect(navigator.current == Position(blockID: 3, sentence: 0))
    }

    @Test func previousWalksBackAndStopsAtTheStart() {
        var navigator = SentenceNavigator(document: document)
        navigator.next(); navigator.next()
        #expect(navigator.previous() == true)
        #expect(navigator.current == Position(blockID: 1, sentence: 0))
        navigator.previous()
        #expect(navigator.previous() == false)
        #expect(navigator.current == Position(blockID: 0, sentence: 0))
    }

    @Test func highlightIsOnlyReportedForTheCurrentBlock() {
        var navigator = SentenceNavigator(document: document)
        navigator.next(); navigator.next()
        #expect(navigator.highlight(in: 1) == 5..<9)
        #expect(navigator.highlight(in: 0) == nil)
        #expect(navigator.highlight(in: 2) == nil)
    }

    @Test func aDocumentWithoutStopsHasNoPosition() {
        var navigator = SentenceNavigator(document: ReaderDocument(title: "T", blocks: [
            .init(id: 0, kind: .footnote(marker: "1"), text: "Only a note."),
        ]))
        #expect(navigator.current == nil)
        #expect(navigator.currentRange == nil)
        #expect(navigator.next() == false)
        #expect(navigator.previous() == false)
        #expect(navigator.highlight(in: 0) == nil)
    }

    @Test func scrollAnchorIsTheSentenceMidpointAsAFractionOfItsBlock() {
        var navigator = SentenceNavigator(document: document)
        #expect(navigator.scrollAnchor == 0.5)
        navigator.next(); navigator.next()
        #expect(navigator.scrollAnchor == 7.0 / 9.0)
    }
}
