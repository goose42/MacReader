import Foundation
import Testing
@testable import MacReaderKit

struct HuffCDICDecompressorTests {
    /// Ten symbols whose codes run from one bit to nine, filling the code space; symbol `n` means the letter `A + n`.
    private static let lengths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 9]
    private static let letters = (0..<10).map { Data([UInt8(0x41 + $0)]) }

    private func decompressor(
        compressed: [Int: [Int]] = [:], entriesPerCDIC: Int = 1024
    ) throws -> (HuffCDICDecompressor, HuffCDICFixture) {
        let fixture = HuffCDICFixture(
            lengths: Self.lengths, phrases: Self.letters, compressed: compressed, entriesPerCDIC: entriesPerCDIC)
        return (try HuffCDICDecompressor(huff: fixture.huff, cdics: fixture.cdics), fixture)
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func shortAndLongCodesDecodeToTheirPhrases() throws {
        let (decompressor, fixture) = try decompressor()
        // Codes of one to eight bits are resolved from the first byte; the two nine-bit codes need the second table.
        let data = fixture.encode([0, 1, 2, 8, 9, 3, 7, 6, 9, 0])
        #expect(try text(decompressor.decompress(data)) == "ABCIJDHGJA")
    }

    @Test func aSingleCodeAndNothingElseGivesNothing() throws {
        let (decompressor, fixture) = try decompressor()
        #expect(try decompressor.decompress(fixture.encode([])).isEmpty)
    }

    @Test func aPhraseCanItselfBeCompressed() throws {
        // Symbol 5 stands for "AB" followed by "C", written as the codes of symbols 0, 1 and 2.
        let (decompressor, fixture) = try decompressor(compressed: [5: [0, 1, 2]])
        #expect(try text(decompressor.decompress(fixture.encode([5, 3, 5]))) == "ABCDABC")
    }

    @Test func aDictionaryMaySpanSeveralRecords() throws {
        let (decompressor, fixture) = try decompressor(entriesPerCDIC: 4)
        #expect(fixture.cdics.count == 3)
        #expect(try text(decompressor.decompress(fixture.encode([9, 8, 7, 0, 5, 3]))) == "JIHAFD")
    }

    @Test func theSameDecompressorReadsManyRecords() throws {
        let (decompressor, fixture) = try decompressor(compressed: [4: [1, 1]])
        #expect(try text(decompressor.decompress(fixture.encode([4, 0]))) == "BBA")
        #expect(try text(decompressor.decompress(fixture.encode([0, 4]))) == "ABB")
        #expect(try text(decompressor.decompress(fixture.encode([4, 4]))) == "BBBB")
    }

    @Test func aBadHeaderIsRejected() throws {
        let fixture = HuffCDICFixture(lengths: Self.lengths, phrases: Self.letters)
        var huff = fixture.huff
        huff[0] = 0x58
        #expect(throws: HuffCDICDecompressor.Failure.invalidHuff) { try HuffCDICDecompressor(huff: huff, cdics: fixture.cdics) }
        #expect(throws: HuffCDICDecompressor.Failure.invalidHuff) { try HuffCDICDecompressor(huff: Data(), cdics: fixture.cdics) }

        var cdic = fixture.cdics[0]
        cdic[0] = 0x58
        #expect(throws: HuffCDICDecompressor.Failure.invalidCDIC) { try HuffCDICDecompressor(huff: fixture.huff, cdics: [cdic]) }
    }

    @Test func aCodeWithNoPhraseIsCorrupt() throws {
        let fixture = HuffCDICFixture(lengths: Self.lengths, phrases: Self.letters)
        // Leave out the dictionary: every code now points past its end.
        let decompressor = try HuffCDICDecompressor(huff: fixture.huff, cdics: [])
        #expect(throws: HuffCDICDecompressor.Failure.corrupt) { try decompressor.decompress(fixture.encode([0, 1])) }
    }
}
