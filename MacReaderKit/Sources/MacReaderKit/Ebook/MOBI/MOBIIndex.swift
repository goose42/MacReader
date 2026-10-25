import Foundation

/// One of the indexes of a KF8 book (skeletons, fragments, the contents). An index is a header record that says which
/// tags its entries can carry, then data records of entries, then records of strings (the CTOC) the entries refer to.
struct MOBIIndex: Sendable {
    enum Failure: Error, Equatable { case corrupt }

    struct Entry: Sendable {
        var label: Data
        /// The values of each tag the entry carries.
        var tags: [Int: [Int]]
    }

    private struct TagRow {
        var number: Int
        var valuesPerEntry: Int
        var mask: Int
        var endsControlByte: Bool
    }

    var entries: [Entry] = []
    /// CTOC strings by the offset at which each starts in its record.
    var strings: [Int: String] = [:]

    /// - Parameters:
    ///   - index: the number of the index's header record.
    ///   - record: the record with a given number, in the same numbering as `index`.
    init(recordAt index: Int, encoding: String.Encoding, record: (Int) -> Data?) throws {
        guard let header = record(index).map(Data.init), header.prefix(4) == Data("INDX".utf8) else { throw Failure.corrupt }
        let headerLength = try Self.integer(header, 4)
        let recordCount = try Self.integer(header, 24)
        let stringRecords = try Self.integer(header, 52)

        // The table of tags sits just after the header, and says how the entries' control bytes are read.
        guard headerLength + 12 <= header.count, header[headerLength..<headerLength + 4] == Data("TAGX".utf8) else { throw Failure.corrupt }
        let firstRow = try Self.integer(header, headerLength + 4)
        let controlBytes = try Self.integer(header, headerLength + 8)
        guard firstRow >= 12, headerLength + firstRow <= header.count else { throw Failure.corrupt }
        var table: [TagRow] = []
        for offset in stride(from: 12, to: firstRow, by: 4) {
            let row = headerLength + offset
            table.append(TagRow(
                number: Int(header[row]), valuesPerEntry: Int(header[row + 1]), mask: Int(header[row + 2]),
                endsControlByte: header[row + 3] == 1))
        }

        for number in stride(from: index + 1, through: index + recordCount, by: 1) {
            guard let data = record(number).map(Data.init), data.prefix(4) == Data("INDX".utf8) else { throw Failure.corrupt }
            let tableStart = try Self.integer(data, 20)
            let count = try Self.integer(data, 24)
            guard tableStart + 4 + 2 * count <= data.count else { throw Failure.corrupt }
            var starts = try (0..<count).map { try Self.integer(data, tableStart + 4 + 2 * $0, size: 2) }
            starts.append(tableStart)

            for entry in 0..<count {
                let start = starts[entry]
                let end = starts[entry + 1]
                guard start < end, end <= data.count else { throw Failure.corrupt }
                let labelLength = Int(data[start])
                guard start + 1 + labelLength <= end else { throw Failure.corrupt }
                let tags = try Self.tags(
                    in: data, from: start + 1 + labelLength, to: end, table: table, controlBytes: controlBytes)
                entries.append(Entry(label: Data(data[start + 1..<start + 1 + labelLength]), tags: tags))
            }
        }

        var offsetBase = 0
        for number in stride(from: index + recordCount + 1, to: index + recordCount + 1 + stringRecords, by: 1) {
            guard let data = record(number).map(Data.init) else { throw Failure.corrupt }
            var position = 0
            while position < data.count, data[position] != 0 {
                let start = position
                let (consumed, length) = try Self.variableWidth(data, at: position)
                position += consumed
                guard position + length <= data.count else { throw Failure.corrupt }
                strings[offsetBase + start] = String(data: data[position..<position + length], encoding: encoding)
                    ?? String(decoding: data[position..<position + length], as: UTF8.self)
                position += length
            }
            offsetBase += 0x10000
        }
    }

    /// Reads one entry's tags: the control bytes say which tags are present and how many values each has, and the
    /// values follow as variable-width numbers.
    private static func tags(
        in data: Data, from start: Int, to end: Int, table: [TagRow], controlBytes: Int
    ) throws -> [Int: [Int]] {
        guard start + controlBytes <= end else { throw Failure.corrupt }
        var position = start + controlBytes
        var control = 0
        // (tag, number of value groups or nil, number of bytes or nil, values per group)
        var present: [(number: Int, groups: Int?, bytes: Int?, perGroup: Int)] = []

        for row in table {
            if row.endsControlByte {
                control += 1
                continue
            }
            guard control < controlBytes else { throw Failure.corrupt }
            var value = Int(data[start + control]) & row.mask
            guard value != 0 else { continue }
            if value == row.mask {
                if row.mask.nonzeroBitCount > 1 {
                    let (consumed, bytes) = try variableWidth(data, at: position)
                    position += consumed
                    present.append((row.number, nil, bytes, row.valuesPerEntry))
                } else {
                    present.append((row.number, 1, nil, row.valuesPerEntry))
                }
            } else {
                value >>= row.mask.trailingZeroBitCount
                present.append((row.number, value, nil, row.valuesPerEntry))
            }
        }

        var tags: [Int: [Int]] = [:]
        for item in present {
            var values: [Int] = []
            if let groups = item.groups {
                for _ in 0..<groups * item.perGroup {
                    let (consumed, value) = try variableWidth(data, at: position)
                    position += consumed
                    values.append(value)
                }
            } else if let bytes = item.bytes {
                var used = 0
                while used < bytes {
                    let (consumed, value) = try variableWidth(data, at: position)
                    position += consumed
                    used += consumed
                    values.append(value)
                }
            }
            tags[item.number] = values
        }
        return tags
    }

    /// A number written 7 bits at a time, most significant first, with the last byte marked by its high bit.
    private static func variableWidth(_ data: Data, at start: Int) throws -> (consumed: Int, value: Int) {
        var value = 0
        var consumed = 0
        while true {
            guard start + consumed < data.count, consumed < 9 else { throw Failure.corrupt }
            let byte = data[data.startIndex + start + consumed]
            consumed += 1
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 != 0 { return (consumed, value) }
        }
    }

    private static func integer(_ data: Data, _ offset: Int, size: Int = 4) throws -> Int {
        guard offset >= 0, offset + size <= data.count else { throw Failure.corrupt }
        return (0..<size).reduce(0) { $0 << 8 | Int(data[data.startIndex + offset + $1]) }
    }
}
