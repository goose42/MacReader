import Foundation
import Testing
@testable import MacReaderKit

struct MOBIBookTests {
    private func book(_ spec: MOBIFixture.Spec) throws -> MOBIBook {
        try MOBIBook(database: PalmDatabase(data: MOBIFixture.build(spec)))
    }

    private func longText(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(0x61 + $0 % 26) })
    }

    // MARK: Text

    @Test func joinsTheTextRecords() throws {
        var spec = MOBIFixture.Spec()
        spec.text = longText(10_000)
        #expect(try book(spec).text() == spec.text)
    }

    @Test func decompressesPalmDOCRecords() throws {
        var spec = MOBIFixture.Spec()
        spec.text = Data("Caf\u{E9} \u{201C}quoted\u{201D}\u{0}\u{1}".utf8) + longText(9000)
        spec.compression = 2
        #expect(try book(spec).text() == spec.text)
    }

    @Test func stripsTheDataThatTrailsEachRecord() throws {
        var spec = MOBIFixture.Spec()
        spec.text = longText(9000)
        spec.extraDataFlags = 3
        #expect(try book(spec).text() == spec.text)

        spec.extraDataFlags = 2
        spec.compression = 2
        #expect(try book(spec).text() == spec.text)
    }

    @Test func decompressesHuffmanRecords() throws {
        let fixture = HuffCDICFixture(
            lengths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 9], phrases: (0..<10).map { Data([UInt8(0x41 + $0)]) })
        var spec = MOBIFixture.Spec()
        spec.compression = 17480
        spec.huffman = fixture
        spec.textRecords = [fixture.encode([0, 1, 2, 3]), fixture.encode([9, 8, 7])]
        #expect(try book(spec).text() == Data("ABCDJIH".utf8))
    }

    @Test func anUnknownCompressionIsUnsupported() throws {
        var spec = MOBIFixture.Spec()
        spec.compression = 3
        let book = try book(spec)
        #expect(throws: MOBIBook.Failure.unsupportedCompression) { try book.text() }
    }

    @Test func aMissingTextRecordIsCorrupt() throws {
        // The header says there is a text record, but the file ends after the header.
        let whole = try PalmDatabase(data: MOBIFixture.build(MOBIFixture.Spec()))
        let headerOnly = try PalmDatabase(data: PalmFixture.database(records: [try #require(whole.record(at: 0))]))
        let book = try MOBIBook(database: headerOnly)
        #expect(throws: MOBIBook.Failure.corrupt) { try book.text() }
    }

    @Test func anOrdinaryDatabaseIsNotAMOBIBook() throws {
        let database = try PalmDatabase(data: PalmFixture.database(records: [Data(count: 300)]))
        #expect(throws: MOBIBook.Failure.notMOBI) { try MOBIBook(database: database) }
    }

    // MARK: Records

    @Test func recordsAreNumberedFromTheBooksFirst() throws {
        let database = try PalmDatabase(data: MOBIFixture.build(MOBIFixture.Spec()))
        let whole = try MOBIBook(database: database)
        #expect(whole.record(1) == database.record(at: 1))
        #expect(whole.record(99) == nil)
    }

    // MARK: Trailing data

    @Test func nothingTrailsWhenNoFlagIsSet() {
        #expect(MOBIBook.trailingSize(of: Data("Hello".utf8), flags: 0) == 0)
    }

    @Test func anEntryCountsItsOwnSizeByte() {
        // "Z" and the size byte: size 2, with the high bit marking the end of the number.
        let record = Data("Hello".utf8) + Data([0x5A, 0x82])
        #expect(MOBIBook.trailingSize(of: record, flags: 2) == 2)
    }

    @Test func aSplitCharacterIsCountedFromItsLowBits() {
        // Two bytes of a character that the boundary cut, then the byte that says so, then an entry.
        let record = Data("Hi".utf8) + Data([0xE2, 0x80, 0x02]) + Data([0x5A, 0x82])
        #expect(MOBIBook.trailingSize(of: record, flags: 3) == 2 + 3)
        #expect(MOBIBook.trailingSize(of: Data("Hi".utf8) + Data([0xE2, 0x80, 0x02]), flags: 1) == 3)
    }

    @Test func aSizeCanTakeTwoBytes() {
        // 128 bytes of entry and two of size: 130, written low seven bits first when read from the end.
        let record = Data("text".utf8) + Data(repeating: 0x41, count: 128) + Data([0x81, 0x02])
        #expect(MOBIBook.trailingSize(of: record, flags: 2) == 130)
    }

    @Test func entriesStackFromTheEndInFlagOrder() {
        // Flag bit 1 is the last entry (size 2), bit 2 the one before it (size 3).
        let record = Data("text".utf8) + Data([0x01, 0x02, 0x83]) + Data([0x09, 0x82])
        #expect(MOBIBook.trailingSize(of: record, flags: 6) == 5)
    }

    @Test func neverMoreThanTheRecord() {
        #expect(MOBIBook.trailingSize(of: Data([0xFF]), flags: 2) <= 1)
        #expect(MOBIBook.trailingSize(of: Data(), flags: 3) == 0)
    }
}
