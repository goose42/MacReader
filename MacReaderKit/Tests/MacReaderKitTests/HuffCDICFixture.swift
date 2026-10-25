import Foundation

/// Builds the HUFF and CDIC records of a Huffman-compressed MOBI, and text compressed with them, so the decoder can
/// be tested without a real file of that kind.
///
/// Symbols are numbered by position in `lengths`. Codes are assigned the way MOBI does: shortest first, and from the
/// largest code downward, so a dictionary slot is the code's distance below the largest code of its length plus the
/// number of shorter codes.
final class HuffCDICFixture {
    private(set) var huff = Data()
    private(set) var cdics: [Data] = []
    private let codes: [Int: (code: Int, length: Int)]
    private let lengths: [Int]

    /// - Parameters:
    ///   - lengths: the code length of each symbol, 1 to 32; they must fill the code space exactly.
    ///   - phrases: what each symbol expands to.
    ///   - compressed: symbols whose phrase is itself written as a sequence of symbols, to be expanded again.
    ///   - entriesPerCDIC: how many dictionary entries each CDIC record holds, a power of two.
    init(lengths: [Int], phrases: [Data], compressed: [Int: [Int]] = [:], entriesPerCDIC: Int = 1024) {
        self.lengths = lengths
        let order = lengths.indices.sorted { (lengths[$0], $0) < (lengths[$1], $1) }

        var codes: [Int: (code: Int, length: Int)] = [:]
        var smallest: [Int: Int] = [:]
        var adjusted: [Int: Int] = [:]
        var remaining = 1 << 32
        var shorter = 0
        for length in 1...32 {
            let group = order.filter { lengths[$0] == length }
            if group.isEmpty { continue }
            let largest = (remaining >> (32 - length)) - 1
            for (offset, symbol) in group.enumerated() { codes[symbol] = (largest - offset, length) }
            smallest[length] = largest - group.count + 1
            adjusted[length] = largest + shorter
            remaining -= group.count << (32 - length)
            shorter += group.count
        }
        self.codes = codes

        // The first eight bits of a code index the table; a code of eight bits or fewer is complete there.
        var table = Data()
        for prefix in 0..<256 {
            let left = prefix << 24
            let short = codes.values.first { entry in
                entry.length <= 8 && left >= entry.code << (32 - entry.length) && left < (entry.code + 1) << (32 - entry.length)
            }
            if let short {
                table.append(be32: (adjusted[short.length]! << 8) | 0x80 | short.length)
            } else {
                table.append(be32: 9)
            }
        }
        var bounds = Data()
        for length in 1...32 {
            bounds.append(be32: smallest[length] ?? 0xFFFF_FFFF)
            bounds.append(be32: adjusted[length] ?? 0)
        }
        huff.append(Data("HUFF".utf8))
        huff.append(be32: 0x18)
        huff.append(be32: 24)
        huff.append(be32: 24 + table.count)
        huff.append(Data(count: 8))
        huff.append(table)
        huff.append(bounds)

        // A phrase is stored by slot, which is its symbol's place in code order.
        var slots: [(data: Data, literal: Bool)] = []
        for symbol in order {
            if let sequence = compressed[symbol] {
                slots.append((encode(sequence), false))
            } else {
                slots.append((phrases[symbol], true))
            }
        }
        var bits = 0
        while 1 << bits < entriesPerCDIC { bits += 1 }
        for start in stride(from: 0, to: slots.count, by: entriesPerCDIC) {
            let chunk = slots[start..<min(start + entriesPerCDIC, slots.count)]
            var offsets = Data()
            var body = Data()
            for slot in chunk {
                offsets.append(be16: 2 * chunk.count + body.count)
                body.append(be16: slot.data.count | (slot.literal ? 0x8000 : 0))
                body.append(slot.data)
            }
            var record = Data("CDIC".utf8)
            record.append(be32: 0x10)
            record.append(be32: slots.count)
            record.append(be32: bits)
            record.append(offsets)
            record.append(body)
            cdics.append(record)
        }
    }

    /// The symbols as a bit stream. A last code is added that ends exactly on the final byte: the decoder stops
    /// when it has consumed every bit, and does not keep what it read last.
    func encode(_ symbols: [Int]) -> Data {
        var bits: [UInt8] = []
        func append(_ symbol: Int) {
            let entry = codes[symbol]!
            for shift in (0..<entry.length).reversed() { bits.append(UInt8((entry.code >> shift) & 1)) }
        }
        symbols.forEach(append)
        let needed = (8 - bits.count % 8) % 8
        append(lengths.firstIndex(of: needed == 0 ? 8 : needed)!)

        var bytes = Data()
        for start in stride(from: 0, to: bits.count, by: 8) {
            bytes.append(bits[start..<start + 8].reduce(0) { $0 << 1 | $1 })
        }
        return bytes
    }
}
