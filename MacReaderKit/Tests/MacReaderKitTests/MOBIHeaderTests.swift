import Foundation
import Testing
@testable import MacReaderKit

struct MOBIHeaderTests {
    private func header(_ spec: MOBIFixture.Spec) throws -> MOBIHeader {
        let database = try PalmDatabase(data: MOBIFixture.build(spec))
        return try MOBIHeader(record: try #require(database.record(at: 0)))
    }

    @Test func readsThePalmDOCAndMOBIFields() throws {
        var spec = MOBIFixture.Spec(title: "Alice's Adventures")
        spec.text = Data(String(repeating: "x", count: 9000).utf8)
        spec.compression = 2
        spec.version = 6
        spec.images = [Data([1]), Data([2])]
        let header = try header(spec)

        #expect(header.compression == 2)
        #expect(header.textLength == 9000)
        #expect(header.textRecordCount == 3)
        #expect(header.encryption == 0)
        #expect(header.encoding == 65001)
        #expect(header.stringEncoding == .utf8)
        #expect(header.version == 6)
        #expect(header.fullName == "Alice's Adventures")
        #expect(header.firstImageRecord == 4)
        #expect(header.huffmanRecord == nil)
    }

    @Test func aBookWithNoPicturesHasNoFirstImage() throws {
        #expect(try header(MOBIFixture.Spec()).firstImageRecord == nil)
    }

    @Test func windows1252IsTheOtherEncoding() throws {
        var spec = MOBIFixture.Spec()
        spec.encoding = 1252
        let header = try header(spec)
        #expect(header.encoding == 1252)
        #expect(header.stringEncoding == .windowsCP1252)
    }

    @Test func readsTheExtraDataFlags() throws {
        var spec = MOBIFixture.Spec()
        spec.extraDataFlags = 3
        #expect(try header(spec).extraDataFlags == 3)
    }

    @Test func readsTheEncryptionType() throws {
        var spec = MOBIFixture.Spec()
        spec.encryption = 2
        #expect(try header(spec).encryption == 2)
    }

    @Test func readsTheHuffmanRecords() throws {
        var spec = MOBIFixture.Spec()
        spec.compression = 17480
        spec.huffman = HuffCDICFixture(lengths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 9], phrases: (0..<10).map { Data([UInt8(0x41 + $0)]) })
        spec.textRecords = [Data([0])]
        let header = try header(spec)
        #expect(header.huffmanRecord == 2)
        #expect(header.huffmanRecordCount == 2)
    }

    // MARK: EXTH

    @Test func readsExthMetadata() throws {
        var spec = MOBIFixture.Spec()
        spec.exth = [
            MOBIFixture.exth(100, "Lewis Carroll"),
            MOBIFixture.exth(101, "Macmillan"),
            MOBIFixture.exth(105, "Fantasy"),
            MOBIFixture.exth(105, "Children's stories"),
            MOBIFixture.exth(503, "Alice in Wonderland"),
            MOBIFixture.exth(121, number: 74),
        ]
        let header = try header(spec)

        #expect(header.string(100) == "Lewis Carroll")
        #expect(header.string(101) == "Macmillan")
        #expect(header.strings(105) == ["Fantasy", "Children's stories"])
        #expect(header.string(503) == "Alice in Wonderland")
        #expect(header.string(999) == nil)
        #expect(header.strings(999).isEmpty)
        #expect(header.integer(121) == 74)
        #expect(header.kf8Record == 74)
        #expect(header.fullName == "A Test Book")
    }

    @Test func aBookWithoutExthHasNone() throws {
        let header = try header(MOBIFixture.Spec())
        #expect(header.exth.isEmpty)
        #expect(header.kf8Record == nil)
    }

    // MARK: Rejection

    @Test func somethingThatIsNotAMOBIRecordIsRejected() {
        #expect(throws: MOBIHeader.Failure.notMOBI) { try MOBIHeader(record: Data()) }
        #expect(throws: MOBIHeader.Failure.notMOBI) { try MOBIHeader(record: Data(count: 200)) }
    }

    @Test func aTruncatedRecordDoesNotCrash() throws {
        let database = try PalmDatabase(data: MOBIFixture.build(MOBIFixture.Spec()))
        let record = try #require(database.record(at: 0))
        for length in [32, 60, 100, 140, 200] {
            _ = try MOBIHeader(record: record.prefix(length))
        }
    }
}
