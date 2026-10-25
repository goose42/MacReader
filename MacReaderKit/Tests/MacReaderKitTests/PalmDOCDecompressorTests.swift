import Foundation
import Testing
@testable import MacReaderKit

struct PalmDOCDecompressorTests {
    private func decompress(_ bytes: [UInt8]) throws -> [UInt8] {
        Array(try PalmDOCDecompressor.decompress(Data(bytes)))
    }

    @Test func printableBytesAreLiterals() throws {
        #expect(try decompress([0x48, 0x65, 0x6C, 0x6C, 0x6F]) == Array("Hello".utf8))
        #expect(try decompress([0x00, 0x09, 0x7F]) == [0x00, 0x09, 0x7F])
    }

    @Test func aCountOfOneToEightCopiesThatManyBytesVerbatim() throws {
        #expect(try decompress([0x03, 0x80, 0x90, 0xFF, 0x41]) == [0x80, 0x90, 0xFF, 0x41])
        #expect(try decompress([0x01, 0x02]) == [0x02])
    }

    @Test func aHighByteIsASpaceFollowedByACharacter() throws {
        #expect(try decompress([0xC1]) == [0x20, 0x41])
        #expect(try decompress([0x48, 0xE9]) == [0x48, 0x20, 0x69])
    }

    @Test func aPairCopiesEarlierOutput() throws {
        // "abc" then copy 6 bytes from 3 back: distance 3, length 6 is 0x8000 | 3 << 3 | (6 - 3).
        #expect(try decompress([0x61, 0x62, 0x63, 0x80, 0x1B]) == Array("abcabcabc".utf8))
    }

    @Test func aPairMayOverlapItsOwnOutput() throws {
        // "a" then copy 5 bytes from 1 back.
        #expect(try decompress([0x61, 0x80, 0x0A]) == Array("aaaaaa".utf8))
    }

    @Test func aReferenceBeforeTheStartIsCorrupt() {
        #expect(throws: PalmDOCDecompressor.Failure.corrupt) { try decompress([0x61, 0x80, 0x1B]) }
        #expect(throws: PalmDOCDecompressor.Failure.corrupt) { try decompress([0x80, 0x1B]) }
    }

    @Test func aTruncatedRunKeepsWhatIsThere() throws {
        #expect(try decompress([0x05, 0x41, 0x42]) == [0x41, 0x42])
        #expect(try decompress([0x61, 0x80]) == [0x61])
    }

    @Test func emptyInputGivesEmptyOutput() throws {
        #expect(try decompress([]).isEmpty)
    }
}
