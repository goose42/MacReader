import Foundation
import Testing
@testable import MacReaderKit

struct KF8BookTests {
    private func kf8(_ spec: KF8Fixture.Spec) throws -> KF8Book {
        let database = try PalmDatabase(data: KF8Fixture.build(spec))
        return try KF8Book(book: MOBIBook(database: database))
    }

    private func text(_ part: KF8Book.Part) -> String { String(decoding: part.data, as: UTF8.self) }

    // MARK: Assembling parts

    private func assemble(
        _ flow: String, skeletons: [KF8Book.Skeleton], fragments: [KF8Book.Fragment]
    ) throws -> [String] {
        try KF8Book.assemble(flow: Data(flow.utf8), skeletons: skeletons, fragments: fragments).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func aSkeletonWithoutFragmentsIsItself() throws {
        let parts = try assemble("<html><body></body></html>", skeletons: [.init(fragmentCount: 0, start: 0, length: 26)], fragments: [])
        #expect(parts == ["<html><body></body></html>"])
    }

    @Test func fragmentsGoIntoTheirSkeletonInOrder() throws {
        // Skeleton "<html><body></body></html>" (26 bytes), then its fragments; "<body>" ends at 12.
        let flow = "<html><body></body></html><p>One</p><p>Two</p>"
        let parts = try assemble(
            flow, skeletons: [.init(fragmentCount: 2, start: 0, length: 26)],
            fragments: [.init(insertPosition: 12, length: 10), .init(insertPosition: 22, length: 10)])
        #expect(parts == ["<html><body><p>One</p><p>Two</p></body></html>"])
    }

    @Test func aSecondSkeletonIsPositionedBeyondTheFirstOnesFragments() throws {
        let flow = "<a></a><i>1</i><b></b><i>2</i><i>3</i>"
        let parts = try assemble(
            flow, skeletons: [.init(fragmentCount: 1, start: 0, length: 7), .init(fragmentCount: 2, start: 15, length: 7)],
            fragments: [
                .init(insertPosition: 3, length: 8), .init(insertPosition: 18, length: 8), .init(insertPosition: 26, length: 8),
            ])
        #expect(parts == ["<a><i>1</i></a>", "<b><i>2</i><i>3</i></b>"])
    }

    @Test func aPositionInsideATagMovesPastIt() throws {
        // The table says 9, which is inside "<body id=x>"; the fragment belongs after the tag.
        let flow = "<html><body id=x></body></html><p>Hi</p>"
        let parts = try assemble(
            flow, skeletons: [.init(fragmentCount: 1, start: 0, length: 31)], fragments: [.init(insertPosition: 9, length: 9)])
        #expect(parts == ["<html><body id=x><p>Hi</p></body></html>"])
    }

    @Test func tablesThatDisagreeWithTheTextAreCorrupt() {
        let flow = Data("<html></html><p>Hi</p>".utf8)
        // A skeleton past the end of the text.
        #expect(throws: KF8Book.Failure.corrupt) {
            try KF8Book.assemble(flow: flow, skeletons: [.init(fragmentCount: 0, start: 10, length: 100)], fragments: [])
        }
        // A skeleton that claims a fragment the table doesn't have.
        #expect(throws: KF8Book.Failure.corrupt) {
            try KF8Book.assemble(flow: flow, skeletons: [.init(fragmentCount: 1, start: 0, length: 13)], fragments: [])
        }
        // A fragment that runs past the end of the text.
        #expect(throws: KF8Book.Failure.corrupt) {
            try KF8Book.assemble(
                flow: flow, skeletons: [.init(fragmentCount: 1, start: 0, length: 13)], fragments: [.init(insertPosition: 6, length: 100)])
        }
        // A position outside the skeleton.
        #expect(throws: KF8Book.Failure.corrupt) {
            try KF8Book.assemble(
                flow: flow, skeletons: [.init(fragmentCount: 1, start: 0, length: 13)], fragments: [.init(insertPosition: 900, length: 9)])
        }
    }

    // MARK: Reading a whole book

    @Test func readsPartsFlowsAndTitles() throws {
        var spec = KF8Fixture.Spec()
        spec.parts = [
            .init(fragments: ["<h1>One</h1><p>First.</p>"], title: "Chapter One"),
            .init(fragments: ["<p>Second</p>", "<p> half.</p>"], title: "Chapter Two"),
            .init(fragments: ["<p>Untitled.</p>"]),
        ]
        spec.flows = ["body { margin: 0 }", "<svg/>"]
        let book = try kf8(spec)

        #expect(book.parts.count == 3)
        #expect(text(book.parts[0]) == "<html><head><title>t</title></head><body><h1>One</h1><p>First.</p></body></html>")
        #expect(text(book.parts[1]).contains("<p>Second</p><p> half.</p>"))
        #expect(book.parts.map(\.title) == ["Chapter One", "Chapter Two", nil])
        #expect(book.flows.count == 3)
        #expect(String(decoding: book.flows[1], as: UTF8.self) == "body { margin: 0 }")
        #expect(String(decoding: book.flows[2], as: UTF8.self) == "<svg/>")
    }

    @Test func aBookWithoutContentsHasUntitledParts() throws {
        var spec = KF8Fixture.Spec()
        spec.parts = [.init(fragments: ["<p>x</p>"]), .init(fragments: ["<p>y</p>"])]
        #expect(try kf8(spec).parts.map(\.title) == [nil, nil])
    }

    @Test func compressedRecordsWithTrailingDataReadTheSame() throws {
        var spec = KF8Fixture.Spec()
        spec.parts = [.init(fragments: [String(repeating: "<p>word</p>", count: 40)], title: "Long")]
        spec.recordSize = 128
        spec.extraDataFlags = 3
        let book = try kf8(spec)
        #expect(text(book.parts[0]).contains(String(repeating: "<p>word</p>", count: 40)))
        #expect(book.parts[0].title == "Long")
    }

    @Test func aBookWithoutIndexesIsCorrupt() throws {
        var header = MOBIFixture.Spec()
        header.version = 8
        let record = MOBIFixture.firstRecord(
            header, textRecordCount: 1, textLength: 5, huffmanRecord: 0, huffmanCount: 0, firstImage: 0xFFFF_FFFF,
            kf8: MOBIFixture.KF8Indexes())
        let book = try MOBIBook(database: PalmDatabase(data: PalmFixture.database(records: [record, Data("text".utf8)])))
        #expect(throws: KF8Book.Failure.corrupt) { try KF8Book(book: book) }
    }
}

/// The same checks on a real KF8 file: *Alice's Adventures in Wonderland*, as Calibre writes it.
struct RealKF8BookTests {
    private func book() throws -> KF8Book {
        let url = try #require(Bundle.module.url(forResource: "alice-kf8.azw3", withExtension: nil, subdirectory: "Fixtures/Ebook"))
        return try KF8Book(book: MOBIBook(database: PalmDatabase(data: Data(contentsOf: url))))
    }

    @Test func theSkeletonAndFragmentTablesRebuildTheFiles() throws {
        let book = try book()
        #expect(book.parts.count == 19)
        #expect(book.flows.count == 5)
        for part in book.parts { _ = try XHTMLParser.parse(part.data) }
        #expect(book.parts.contains { String(decoding: $0.data, as: UTF8.self).contains("Alice was beginning to get very tired") })
    }

    @Test func theContentsIndexTitlesTheFilesChaptersAreIn() throws {
        let titles = try book().parts.compactMap(\.title)
        #expect(titles.contains("CHAPTER I. Down the Rabbit-Hole"))
        #expect(titles.contains("CHAPTER XII. Alice’s Evidence"))
        #expect(titles.first == "Alice’s Adventures in Wonderland")
    }
}
