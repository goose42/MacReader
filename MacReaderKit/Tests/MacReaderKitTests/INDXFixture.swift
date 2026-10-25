import Foundation

/// Builds the INDX records of a KF8 book (skeleton, fragment and contents indexes) for tests.
enum INDXFixture {
    struct Tag {
        var number: Int
        var valuesPerEntry: Int
        var mask: Int
        /// A row that ends a control byte rather than describing a tag.
        var isEnd = false
    }

    struct Entry {
        var label: String
        var tags: [Int: [Int]] = [:]
    }

    struct Built {
        /// The header record, the data records, and the CTOC record if there are strings.
        var records: [Data]
        /// Where each string starts within the CTOC record, which is how entries refer to them.
        var stringOffsets: [Int]
    }

    static func variableWidth(_ value: Int) -> [UInt8] {
        var groups = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            groups.insert(UInt8(rest & 0x7F), at: 0)
            rest >>= 7
        }
        groups[groups.count - 1] |= 0x80
        return groups
    }

    static func build(
        tags: [Tag], controlBytes: Int = 1, entries: [Entry], strings: [String] = [], entriesPerRecord: Int = 1000
    ) -> Built {
        var records: [Data] = []

        var tagx = Data("TAGX".utf8)
        tagx.append(be32: 12 + 4 * tags.count)
        tagx.append(be32: controlBytes)
        for tag in tags { tagx.append(contentsOf: [UInt8(tag.number), UInt8(tag.valuesPerEntry), UInt8(tag.mask), tag.isEnd ? 1 : 0]) }

        let chunks = stride(from: 0, to: max(entries.count, 1), by: entriesPerRecord).map {
            Array(entries[$0..<min($0 + entriesPerRecord, entries.count)])
        }

        var header = Data(count: 192)
        header.replaceSubrange(0..<4, with: Data("INDX".utf8))
        put(192, into: &header, at: 4)
        put(chunks.count, into: &header, at: 24)
        put(65001, into: &header, at: 28)
        put(entries.count, into: &header, at: 36)
        put(strings.isEmpty ? 0 : 1, into: &header, at: 52)
        header.append(tagx)
        records.append(header)

        for chunk in chunks {
            var record = Data(count: 192)
            record.replaceSubrange(0..<4, with: Data("INDX".utf8))
            put(192, into: &record, at: 4)
            var offsets: [Int] = []
            for entry in chunk {
                offsets.append(record.count)
                let label = Data(entry.label.utf8)
                record.append(UInt8(label.count))
                record.append(label)
                record.append(Data(tagSection(of: entry, tags: tags, controlBytes: controlBytes)))
            }
            put(record.count, into: &record, at: 20)
            put(chunk.count, into: &record, at: 24)
            record.append(Data("IDXT".utf8))
            for offset in offsets { record.append(be16: offset) }
            records.append(record)
        }

        var stringOffsets: [Int] = []
        if !strings.isEmpty {
            var ctoc = Data()
            for string in strings {
                stringOffsets.append(ctoc.count)
                let bytes = Data(string.utf8)
                ctoc.append(contentsOf: variableWidth(bytes.count))
                ctoc.append(bytes)
            }
            ctoc.append(0)
            records.append(ctoc)
        }
        return Built(records: records, stringOffsets: stringOffsets)
    }

    private static func put(_ value: Int, into data: inout Data, at offset: Int) {
        for index in 0..<4 { data[offset + index] = UInt8((value >> (8 * (3 - index))) & 0xFF) }
    }

    /// The control bytes, then any byte counts for tags with a long run of values, then the values.
    private static func tagSection(of entry: Entry, tags: [Tag], controlBytes: Int) -> [UInt8] {
        var control = [UInt8](repeating: 0, count: controlBytes)
        var lengths: [UInt8] = []
        var values: [UInt8] = []
        var index = 0
        for tag in tags {
            if tag.isEnd {
                index += 1
                continue
            }
            guard let numbers = entry.tags[tag.number], !numbers.isEmpty else { continue }
            let count = numbers.count / tag.valuesPerEntry
            let shift = tag.mask.trailingZeroBitCount
            let encoded = numbers.flatMap(variableWidth)
            if count == tag.mask >> shift && tag.mask.nonzeroBitCount > 1 {
                control[index] |= UInt8(tag.mask)
                lengths += variableWidth(encoded.count)
            } else {
                control[index] |= UInt8(count << shift)
            }
            values += encoded
        }
        return control + lengths + values
    }
}
