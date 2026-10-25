import Compression
import Foundation

/// Builds ZIP files in memory for tests, independently of the reader under test.
enum ZipFixture {
    struct Entry {
        var name: String
        var data: Data
        var deflated = false
        var encrypted = false
    }

    static func make(_ entries: [Entry]) -> Data {
        var archive = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let stored = entry.deflated ? deflate(entry.data) : entry.data
            let flags: UInt16 = entry.encrypted ? 1 : 0
            let method: UInt16 = entry.deflated ? 8 : 0
            let crc = crc32(entry.data)
            let offset = UInt32(archive.count)

            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20)
            archive.append(le16: flags)
            archive.append(le16: method)
            archive.append(le16: 0)
            archive.append(le16: 0)
            archive.append(le32: crc)
            archive.append(le32: UInt32(stored.count))
            archive.append(le32: UInt32(entry.data.count))
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)
            archive.append(name)
            archive.append(stored)

            central.append(le32: 0x0201_4B50)
            central.append(le16: 20)
            central.append(le16: 20)
            central.append(le16: flags)
            central.append(le16: method)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le32: crc)
            central.append(le32: UInt32(stored.count))
            central.append(le32: UInt32(entry.data.count))
            central.append(le16: UInt16(name.count))
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le32: 0)
            central.append(le32: offset)
            central.append(name)
        }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(central.count))
        archive.append(le32: centralOffset)
        archive.append(le16: 0)
        return archive
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    /// Raw deflate, which is what `COMPRESSION_ZLIB` produces and what a ZIP entry holds.
    static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + 1024
        var output = [UInt8](repeating: 0, count: capacity)
        let size = data.withUnsafeBytes { source in
            compression_encode_buffer(
                &output, capacity, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return Data(output.prefix(size))
    }
}

extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}
