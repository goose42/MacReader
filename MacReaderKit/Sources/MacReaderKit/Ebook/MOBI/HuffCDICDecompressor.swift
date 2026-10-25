import Foundation

/// Huffman compression with a shared dictionary (HUFF and CDIC records), used by some MOBI books.
///
/// A HUFF record gives, for the first eight bits of a code, either the code's length and the number that turns it into
/// a dictionary slot, or a note to look further in a table of per-length bounds. The CDIC records hold the dictionary:
/// phrases of text, some of which are themselves compressed with the same codes.
struct HuffCDICDecompressor: Sendable {
    enum Failure: Error, Equatable { case invalidHuff, invalidCDIC, corrupt }

    private struct Prefix: Sendable {
        var length: Int
        /// Whether the whole code fits in these eight bits.
        var isComplete: Bool
        /// The largest code of this length, left-aligned in 32 bits; subtracting a code from it, and dropping the
        /// unused low bits, gives the code's dictionary slot.
        var largest: Int
    }

    private struct Phrase: Sendable {
        var data: Data
        var isLiteral: Bool
    }

    private let prefixes: [Prefix]
    /// Indexed by code length, 0 through 32; left-aligned in 32 bits.
    private let smallest: [Int]
    private let largest: [Int]
    private let dictionary: [Phrase]

    init(huff: Data, cdics: [Data]) throws {
        let huff = Data(huff)
        guard huff.count >= 16, huff.prefix(8) == Data([0x48, 0x55, 0x46, 0x46, 0, 0, 0, 0x18]) else { throw Failure.invalidHuff }
        let table = Self.integer(huff, at: 8, size: 4)
        let bounds = Self.integer(huff, at: 12, size: 4)
        guard table + 4 * 256 <= huff.count, bounds + 8 * 32 <= huff.count else { throw Failure.invalidHuff }

        var prefixes: [Prefix] = []
        for index in 0..<256 {
            let value = Self.integer(huff, at: table + 4 * index, size: 4)
            let length = value & 0x1F
            let isComplete = value & 0x80 != 0
            guard length != 0, length > 8 || isComplete else { throw Failure.invalidHuff }
            prefixes.append(Prefix(length: length, isComplete: isComplete, largest: (((value >> 8) + 1) << (32 - length)) - 1))
        }
        self.prefixes = prefixes

        var smallest = [0]
        var largest = [(1 << 32) - 1]
        for length in 1...32 {
            let smallestCode = Self.integer(huff, at: bounds + 8 * (length - 1), size: 4)
            let largestCode = Self.integer(huff, at: bounds + 8 * (length - 1) + 4, size: 4)
            smallest.append(smallestCode << (32 - length))
            largest.append(((largestCode + 1) << (32 - length)) - 1)
        }
        self.smallest = smallest
        self.largest = largest

        var dictionary: [Phrase] = []
        for record in cdics {
            let cdic = Data(record)
            guard cdic.count >= 16, cdic.prefix(8) == Data([0x43, 0x44, 0x49, 0x43, 0, 0, 0, 0x10]) else { throw Failure.invalidCDIC }
            let phrases = Self.integer(cdic, at: 8, size: 4)
            let bits = Self.integer(cdic, at: 12, size: 4)
            guard bits <= 16 else { throw Failure.invalidCDIC }
            let count = max(0, min(1 << bits, phrases - dictionary.count))
            guard 16 + 2 * count <= cdic.count else { throw Failure.invalidCDIC }
            for index in 0..<count {
                let offset = Self.integer(cdic, at: 16 + 2 * index, size: 2)
                guard 16 + offset + 2 <= cdic.count else { throw Failure.invalidCDIC }
                let header = Self.integer(cdic, at: 16 + offset, size: 2)
                let start = 18 + offset
                let end = start + (header & 0x7FFF)
                guard end <= cdic.count else { throw Failure.invalidCDIC }
                dictionary.append(Phrase(data: Data(cdic[start..<end]), isLiteral: header & 0x8000 != 0))
            }
        }
        self.dictionary = dictionary
    }

    func decompress(_ data: Data) throws -> Data {
        var expanded: [Int: Data] = [:]
        return try unpack(data, expanded: &expanded, depth: 0)
    }

    /// Reads codes until every bit is used up. The code that crosses the end is padding, and is not kept.
    private func unpack(_ data: Data, expanded: inout [Int: Data], depth: Int) throws -> Data {
        guard depth < 16 else { throw Failure.corrupt }
        let bytes = [UInt8](data) + [UInt8](repeating: 0, count: 8)
        var bitsLeft = data.count * 8
        var position = 0
        var window = Self.window(bytes, at: 0)
        var shift = 32
        var output = Data()

        while true {
            if shift <= 0 {
                position += 4
                guard position + 8 <= bytes.count else { throw Failure.corrupt }
                window = Self.window(bytes, at: position)
                shift += 32
            }
            let code = Int((window >> UInt64(shift)) & 0xFFFF_FFFF)

            let prefix = prefixes[code >> 24]
            var length = prefix.length
            var largestCode = prefix.largest
            if !prefix.isComplete {
                while code < smallest[length] {
                    length += 1
                    guard length <= 32 else { throw Failure.corrupt }
                }
                largestCode = largest[length]
            }

            shift -= length
            bitsLeft -= length
            if bitsLeft <= 0 { break }

            let slot = (largestCode - code) >> (32 - length)
            guard dictionary.indices.contains(slot) else { throw Failure.corrupt }
            if let phrase = expanded[slot] {
                output.append(phrase)
            } else {
                let entry = dictionary[slot]
                let phrase = entry.isLiteral ? entry.data : try unpack(entry.data, expanded: &expanded, depth: depth + 1)
                expanded[slot] = phrase
                output.append(phrase)
            }
        }
        return output
    }

    private static func integer(_ data: Data, at offset: Int, size: Int) -> Int {
        (0..<size).reduce(0) { $0 << 8 | Int(data[data.startIndex + offset + $1]) }
    }

    private static func window(_ bytes: [UInt8], at position: Int) -> UInt64 {
        (0..<8).reduce(0) { $0 << 8 | UInt64(bytes[position + $1]) }
    }
}
