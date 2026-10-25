import Compression
import Foundation

/// A read-only ZIP file held in memory, which is all an EPUB is. Entries are stored or deflated; encrypted ones are
/// refused rather than read.
struct ZipArchive: Sendable {
    enum Failure: Error, Equatable {
        case notAnArchive
        case missingEntry(String)
        /// The entry's bytes don't match its recorded checksum or size, or run past the end of the file.
        case corrupt(String)
        case encrypted(String)
        case unsupportedMethod(String)
    }

    private struct Entry: Sendable {
        var method: UInt16
        var flags: UInt16
        var crc: UInt32
        var compressedSize: Int
        var size: Int
        var headerOffset: Int
    }

    private let bytes: Data
    private let entries: [String: Entry]
    /// Entry names in the order the archive lists them.
    let names: [String]

    /// The largest entry read, so a forged size can't ask for gigabytes.
    private static let maximumEntryBytes = 512_000_000

    init(data: Data) throws {
        bytes = Data(data)
        let directory = try Self.locateDirectory(in: bytes)

        var entries: [String: Entry] = [:]
        var names: [String] = []
        var position = directory.offset
        for _ in 0..<directory.count {
            guard try Self.u32(bytes, position) == 0x0201_4B50 else { throw Failure.notAnArchive }
            let flags = try Self.u16(bytes, position + 8)
            let method = try Self.u16(bytes, position + 10)
            let crc = try Self.u32(bytes, position + 16)
            var compressed = Int(try Self.u32(bytes, position + 20))
            var size = Int(try Self.u32(bytes, position + 24))
            let nameLength = Int(try Self.u16(bytes, position + 28))
            let extraLength = Int(try Self.u16(bytes, position + 30))
            let commentLength = Int(try Self.u16(bytes, position + 32))
            var headerOffset = Int(try Self.u32(bytes, position + 42))
            let nameStart = position + 46
            guard nameStart + nameLength + extraLength + commentLength <= bytes.count else { throw Failure.notAnArchive }
            let name = String(decoding: bytes[nameStart..<nameStart + nameLength], as: UTF8.self)

            // ZIP64 keeps the values that don't fit in 32 bits in an extra field, in this order.
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = try Self.u16(bytes, extra)
                let length = Int(try Self.u16(bytes, extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    if size == 0xFFFF_FFFF { size = Int(try Self.u64(bytes, field)); field += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = Int(try Self.u64(bytes, field)); field += 8 }
                    if headerOffset == 0xFFFF_FFFF { headerOffset = Int(try Self.u64(bytes, field)) }
                }
                extra += 4 + length
            }

            if entries[name] == nil { names.append(name) }
            entries[name] = Entry(
                method: method, flags: flags, crc: crc, compressedSize: compressed, size: size, headerOffset: headerOffset)
            position = nameStart + nameLength + extraLength + commentLength
        }
        self.entries = entries
        self.names = names
    }

    func contains(_ name: String) -> Bool {
        entry(named: name) != nil
    }

    /// The uncompressed bytes of the entry called `name`. Paths written with percent-escapes, as hrefs are, are
    /// found too.
    func data(for name: String) throws -> Data {
        guard let entry = entry(named: name) else { throw Failure.missingEntry(name) }
        if entry.flags & 1 != 0 { throw Failure.encrypted(name) }
        guard entry.size <= Self.maximumEntryBytes else { throw Failure.corrupt(name) }

        let header = entry.headerOffset
        guard (try? Self.u32(bytes, header)) == 0x0403_4B50,
              let nameLength = try? Self.u16(bytes, header + 26), let extraLength = try? Self.u16(bytes, header + 28)
        else { throw Failure.corrupt(name) }
        let start = header + 30 + Int(nameLength) + Int(extraLength)
        guard entry.compressedSize >= 0, start + entry.compressedSize <= bytes.count else { throw Failure.corrupt(name) }
        let stored = bytes[start..<start + entry.compressedSize]

        let result: Data
        switch entry.method {
        case 0:
            result = Data(stored)
        case 8:
            result = try Self.inflate(stored, size: entry.size, name: name)
        default:
            throw Failure.unsupportedMethod(name)
        }
        guard result.count == entry.size, Self.crc32(result) == entry.crc else { throw Failure.corrupt(name) }
        return result
    }

    private func entry(named name: String) -> Entry? {
        entries[name] ?? name.removingPercentEncoding.flatMap { entries[$0] }
    }

    // MARK: Layout

    /// Finds the central directory by way of the end-of-central-directory record, which sits at the very end unless
    /// a comment follows it.
    private static func locateDirectory(in bytes: Data) throws -> (offset: Int, count: Int) {
        let minimum = 22
        guard bytes.count >= minimum else { throw Failure.notAnArchive }
        let earliest = max(0, bytes.count - minimum - 0xFFFF)
        var end = bytes.count - minimum
        while end >= earliest {
            if (try? u32(bytes, end)) == 0x0605_4B50 { break }
            end -= 1
        }
        guard end >= earliest else { throw Failure.notAnArchive }

        var count = Int(try u16(bytes, end + 10))
        var offset = Int(try u32(bytes, end + 16))
        if (count == 0xFFFF || offset == 0xFFFF_FFFF), end >= 20, try u32(bytes, end - 20) == 0x0706_4B50 {
            let record = Int(try u64(bytes, end - 20 + 8))
            guard try u32(bytes, record) == 0x0606_4B50 else { throw Failure.notAnArchive }
            count = Int(try u64(bytes, record + 32))
            offset = Int(try u64(bytes, record + 48))
        }
        guard offset >= 0, offset <= bytes.count else { throw Failure.notAnArchive }
        return (offset, count)
    }

    private static func inflate(_ stored: Data, size: Int, name: String) throws -> Data {
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let written = stored.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&output, size, base, stored.count, nil, COMPRESSION_ZLIB)
        }
        guard written == size else { throw Failure.corrupt(name) }
        return Data(output)
    }

    // MARK: Bytes

    private static func u16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw Failure.notAnArchive }
        let base = data.startIndex + offset
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw Failure.notAnArchive }
        let base = data.startIndex + offset
        return (0..<4).reduce(0) { $0 | UInt32(data[base + $1]) << (8 * UInt32($1)) }
    }

    private static func u64(_ data: Data, _ offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else { throw Failure.notAnArchive }
        let base = data.startIndex + offset
        return (0..<8).reduce(0) { $0 | UInt64(data[base + $1]) << (8 * UInt64($1)) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1 }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(0xFFFF_FFFF as UInt32) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}
