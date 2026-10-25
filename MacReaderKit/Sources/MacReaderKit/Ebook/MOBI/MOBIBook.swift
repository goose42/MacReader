import Foundation

/// One book inside a Palm database. A file normally holds one, but a "joint" file holds an old-format book and, after a
/// `BOUNDARY` record, a KF8 book whose record numbers count from its own first record (`base`).
struct MOBIBook: Sendable {
    enum Failure: Error, Equatable {
        case notMOBI
        case corrupt
        case unsupportedCompression
    }

    let database: PalmDatabase
    /// The record, in the database, where this book's own record 0 is.
    let base: Int
    let header: MOBIHeader

    init(database: PalmDatabase, base: Int = 0) throws {
        guard let first = database.record(at: base), let header = try? MOBIHeader(record: first) else { throw Failure.notMOBI }
        self.database = database
        self.base = base
        self.header = header
    }

    /// A record by its number within this book.
    func record(_ index: Int) -> Data? {
        database.record(at: base + index)
    }

    /// The book's markup: every text record, stripped of the data that trails it and decompressed, in order.
    func text() throws -> Data {
        let decode: (Data) throws -> Data
        switch header.compression {
        case 1:
            decode = { $0 }
        case 2:
            decode = { try PalmDOCDecompressor.decompress($0) }
        case 17480:
            let decompressor = try huffmanDecompressor()
            decode = { try decompressor.decompress($0) }
        default:
            throw Failure.unsupportedCompression
        }

        var text = Data()
        text.reserveCapacity(header.textLength)
        for index in stride(from: 1, through: header.textRecordCount, by: 1) {
            guard let record = record(index) else { throw Failure.corrupt }
            let kept = record.count - Self.trailingSize(of: record, flags: header.extraDataFlags)
            guard kept >= 0 else { throw Failure.corrupt }
            do { text.append(try decode(record.prefix(kept))) } catch { throw Failure.corrupt }
        }
        return text
    }

    private func huffmanDecompressor() throws -> HuffCDICDecompressor {
        guard let start = header.huffmanRecord, header.huffmanRecordCount >= 2, let huff = record(start) else { throw Failure.corrupt }
        let dictionaries = (1..<header.huffmanRecordCount).compactMap { record(start + $0) }
        do { return try HuffCDICDecompressor(huff: huff, cdics: dictionaries) } catch { throw Failure.corrupt }
    }

    /// How many bytes at the end of a text record are not text. Each flag bit from the second up marks an entry
    /// whose size is a backwards variable-length number in its last bytes; the lowest bit marks the bytes of a
    /// multi-byte character that was cut by the record boundary, counted in the two low bits of the byte before the
    /// entries.
    static func trailingSize(of record: Data, flags: Int) -> Int {
        guard flags != 0 else { return 0 }
        let bytes = [UInt8](record)

        func entrySize(endingBefore end: Int) -> Int {
            var size = 0
            var shift = 0
            var position = end
            while position > 0 {
                let byte = bytes[position - 1]
                size |= Int(byte & 0x7F) << shift
                shift += 7
                position -= 1
                if byte & 0x80 != 0 || shift >= 28 { break }
            }
            return size
        }

        var trailing = 0
        var remaining = flags >> 1
        while remaining != 0 {
            if remaining & 1 != 0 { trailing += entrySize(endingBefore: bytes.count - trailing) }
            remaining >>= 1
        }
        if flags & 1 != 0, bytes.count - trailing - 1 >= 0 {
            trailing += Int(bytes[bytes.count - trailing - 1] & 0x3) + 1
        }
        return min(trailing, bytes.count)
    }
}
