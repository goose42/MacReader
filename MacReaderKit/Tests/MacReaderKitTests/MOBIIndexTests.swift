import Foundation
import Testing
@testable import MacReaderKit

struct MOBIIndexTests {
    private static let skeletonTags: [INDXFixture.Tag] = [
        .init(number: 1, valuesPerEntry: 1, mask: 3), .init(number: 6, valuesPerEntry: 2, mask: 12), .init(number: 0, valuesPerEntry: 0, mask: 0, isEnd: true),
    ]

    private func index(_ built: INDXFixture.Built, at start: Int = 0) throws -> MOBIIndex {
        let records = built.records
        return try MOBIIndex(recordAt: start, encoding: .utf8) { $0 >= 0 && $0 < records.count ? records[$0] : nil }
    }

    @Test func readsLabelsAndTags() throws {
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: [
            .init(label: "SKEL0000000000", tags: [1: [3], 6: [0, 436]]),
            .init(label: "SKEL0000000001", tags: [1: [1], 6: [557, 652]]),
        ])
        let index = try index(built)
        #expect(index.entries.map { String(decoding: $0.label, as: UTF8.self) } == ["SKEL0000000000", "SKEL0000000001"])
        #expect(index.entries[0].tags == [1: [3], 6: [0, 436]])
        #expect(index.entries[1].tags == [1: [1], 6: [557, 652]])
    }

    @Test func anEntryWithNoTagsHasNone() throws {
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: [.init(label: "A"), .init(label: "B", tags: [1: [2]])])
        let index = try index(built)
        #expect(index.entries[0].tags.isEmpty)
        #expect(index.entries[1].tags == [1: [2]])
    }

    @Test func largeNumbersSpanSeveralBytes() throws {
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: [.init(label: "A", tags: [1: [300_000], 6: [0, 16_383]])])
        #expect(try index(built).entries[0].tags == [1: [300_000], 6: [0, 16_383]])
    }

    @Test func aRunAsLongAsTheMaskAllowsIsPrecededByItsByteCount() throws {
        // Mask 12 holds counts up to 3; a count of 3 is written as "all bits set" and then the number of bytes.
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: [.init(label: "A", tags: [6: [1, 2, 3, 4, 5, 200]])])
        #expect(try index(built).entries[0].tags == [6: [1, 2, 3, 4, 5, 200]])
    }

    @Test func tagsInASecondControlByteAreRead() throws {
        let tags: [INDXFixture.Tag] = [
            .init(number: 1, valuesPerEntry: 1, mask: 1), .init(number: 3, valuesPerEntry: 1, mask: 4),
            .init(number: 0, valuesPerEntry: 0, mask: 0, isEnd: true),
            .init(number: 6, valuesPerEntry: 2, mask: 1), .init(number: 0, valuesPerEntry: 0, mask: 0, isEnd: true),
        ]
        let built = INDXFixture.build(tags: tags, controlBytes: 2, entries: [
            .init(label: "00", tags: [1: [3315], 3: [0], 6: [1, 2122]]),
            .init(label: "01", tags: [3: [35]]),
            .init(label: "02", tags: [6: [4, 0]]),
        ])
        let entries = try index(built).entries
        #expect(entries[0].tags == [1: [3315], 3: [0], 6: [1, 2122]])
        #expect(entries[1].tags == [3: [35]])
        #expect(entries[2].tags == [6: [4, 0]])
    }

    @Test func entriesSpreadOverSeveralRecordsAreAllRead() throws {
        let entries = (0..<7).map { INDXFixture.Entry(label: "E\($0)", tags: [1: [$0]]) }
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: entries, entriesPerRecord: 3)
        #expect(built.records.count == 4)
        let index = try index(built)
        #expect(index.entries.count == 7)
        #expect(index.entries.map { $0.tags[1]?.first } == (0..<7).map { Optional($0) })
    }

    @Test func stringsAreFoundByTheirOffsetInTheCTOC() throws {
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: [.init(label: "A", tags: [1: [1]])], strings: ["First", "Chapter Two: Café", String(repeating: "x", count: 200)])
        let index = try index(built)
        #expect(index.strings[built.stringOffsets[0]] == "First")
        #expect(index.strings[built.stringOffsets[1]] == "Chapter Two: Café")
        #expect(index.strings[built.stringOffsets[2]]?.count == 200)
        #expect(index.strings.count == 3)
    }

    @Test func theIndexMayStartAnywhereInTheBook() throws {
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: [.init(label: "A", tags: [1: [7]])], strings: ["s"])
        let padding = [Data(), Data(count: 10)]
        let records = padding + built.records
        let index = try MOBIIndex(recordAt: 2, encoding: .utf8) { records.indices.contains($0) ? records[$0] : nil }
        #expect(index.entries[0].tags == [1: [7]])
        #expect(index.strings[0] == "s")
    }

    @Test func somethingThatIsNotAnIndexIsCorrupt() {
        #expect(throws: MOBIIndex.Failure.corrupt) {
            try MOBIIndex(recordAt: 0, encoding: .utf8) { _ in Data("not an index".utf8) }
        }
        #expect(throws: MOBIIndex.Failure.corrupt) {
            try MOBIIndex(recordAt: 0, encoding: .utf8) { _ in nil }
        }
    }

    @Test func aTruncatedRecordIsCorruptRatherThanACrash() throws {
        let built = INDXFixture.build(tags: Self.skeletonTags, entries: [.init(label: "A", tags: [1: [7]])])
        var records = built.records
        records[1] = records[1].prefix(200)
        #expect(throws: MOBIIndex.Failure.corrupt) {
            try MOBIIndex(recordAt: 0, encoding: .utf8) { records.indices.contains($0) ? records[$0] : nil }
        }
    }
}
