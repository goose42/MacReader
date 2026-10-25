import Foundation

/// Builds Palm databases, the container Kindle books come in, for tests.
enum PalmFixture {
    static func database(name: String = "Book", type: String = "BOOK", creator: String = "MOBI", records: [Data]) -> Data {
        var data = Data()
        var padded = Data(name.utf8.prefix(31))
        padded.append(Data(count: 32 - padded.count))
        data.append(padded)
        data.append(be16: 0)                       // attributes
        data.append(be16: 0)                       // version
        data.append(Data(count: 16))               // dates, modification number
        data.append(Data(count: 8))                // app info, sort info
        data.append(Data(type.utf8.prefix(4)))
        data.append(Data(creator.utf8.prefix(4)))
        data.append(Data(count: 8))                // unique id seed, next record list
        data.append(be16: records.count)

        var offset = 78 + 8 * records.count + 2
        for (index, record) in records.enumerated() {
            data.append(be32: offset)
            data.append(0)                         // attributes
            data.append(contentsOf: [0, 0, UInt8(index & 0xFF)])
            offset += record.count
        }
        data.append(be16: 0)                       // gap before the first record
        for record in records { data.append(record) }
        return data
    }
}

extension Data {
    /// Big-endian, which is how Palm and MOBI files write their numbers.
    mutating func append(be16 value: Int) {
        append(contentsOf: [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func append(be32 value: Int) {
        append(contentsOf: [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
