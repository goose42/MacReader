import Foundation

/// Builds old-format (MOBI 6) books for tests: a Palm database whose first record holds the PalmDOC and MOBI headers
/// and the EXTH metadata, followed by text records and picture records.
enum MOBIFixture {
    struct Spec {
        var title = "A Test Book"
        /// The markup, in the book's encoding.
        var text = Data("<html><body><p>Hello.</p></body></html>".utf8)
        /// 1 for none, 2 for PalmDOC (stored as literals), 17480 for Huffman (see `huffman`).
        var compression = 1
        var encoding = 65001
        var version = 6
        var encryption = 0
        /// Which trailing data is appended to every text record, as the book's header declares it.
        var extraDataFlags = 0
        var recordSize = 4096
        var images: [Data] = []
        var exth: [(type: Int, value: Data)] = []
        var huffman: HuffCDICFixture?
        /// Overrides the text records, for compression the fixture can't produce itself.
        var textRecords: [Data]?
    }

    static func exth(_ type: Int, _ text: String) -> (type: Int, value: Data) { (type, Data(text.utf8)) }

    static func exth(_ type: Int, number: Int) -> (type: Int, value: Data) {
        var data = Data()
        data.append(be32: number)
        return (type, data)
    }

    /// PalmDOC that is valid but uncompressed: plain bytes stay, the rest go in counted literal runs.
    static func palmDOC(_ data: Data) -> Data {
        var output = Data()
        var run: [UInt8] = []
        func flush() {
            guard !run.isEmpty else { return }
            output.append(UInt8(run.count))
            output.append(contentsOf: run)
            run = []
        }
        for byte in data {
            if byte == 0 || (0x09...0x7F).contains(byte) {
                flush()
                output.append(byte)
            } else {
                run.append(byte)
                if run.count == 8 { flush() }
            }
        }
        flush()
        return output
    }

    /// The record that trails text when `extraDataFlags` is 3: a character cut by the record boundary, then one entry.
    static func trailer(for flags: Int) -> Data {
        var trailer = Data()
        if flags & 1 != 0 { trailer.append(contentsOf: [0xE2, 0x80, 0x02]) }
        if flags & 2 != 0 { trailer.append(contentsOf: [0x5A, 0x82]) }
        return trailer
    }

    static func build(_ spec: Spec) -> Data {
        var textChunks: [Data] = []
        for start in stride(from: 0, to: max(spec.text.count, 1), by: spec.recordSize) {
            textChunks.append(Data(spec.text[start..<min(start + spec.recordSize, spec.text.count)]))
        }
        var textRecords: [Data]
        if let override = spec.textRecords {
            textRecords = override
        } else {
            textRecords = textChunks.map { chunk in
                switch spec.compression {
                case 2: palmDOC(chunk)
                default: chunk
                }
            }
        }

        var records: [Data] = [Data()]
        textRecords = textRecords.map { $0 + trailer(for: spec.extraDataFlags) }
        records += textRecords
        let huffmanRecord = records.count
        var huffmanCount = 0
        if let huffman = spec.huffman {
            records.append(huffman.huff)
            records += huffman.cdics
            huffmanCount = 1 + huffman.cdics.count
        }
        let firstImage = records.count
        records += spec.images
        records.append(Data("EOF".utf8))

        records[0] = firstRecord(
            spec, textRecordCount: textRecords.count, huffmanRecord: huffmanRecord, huffmanCount: huffmanCount,
            firstImage: spec.images.isEmpty ? 0xFFFF_FFFF : firstImage)
        return PalmFixture.database(name: "Test_Book", type: "BOOK", creator: "MOBI", records: records)
    }

    private static func firstRecord(
        _ spec: Spec, textRecordCount: Int, huffmanRecord: Int, huffmanCount: Int, firstImage: Int
    ) -> Data {
        let headerLength = 232
        let name = Data(spec.title.utf8)

        var exth = Data()
        if !spec.exth.isEmpty {
            var body = Data()
            for record in spec.exth {
                body.append(be32: record.type)
                body.append(be32: record.value.count + 8)
                body.append(record.value)
            }
            exth.append(Data("EXTH".utf8))
            exth.append(be32: 12 + body.count)
            exth.append(be32: spec.exth.count)
            exth.append(body)
            while exth.count % 4 != 0 { exth.append(0) }
        }

        let nameOffset = 16 + headerLength + exth.count
        var record = Data(count: 16 + headerLength)
        func put(_ value: Int, at offset: Int, size: Int) {
            for index in 0..<size { record[offset + index] = UInt8((value >> (8 * (size - 1 - index))) & 0xFF) }
        }
        put(spec.compression, at: 0, size: 2)
        put(spec.text.count, at: 4, size: 4)
        put(textRecordCount, at: 8, size: 2)
        put(spec.recordSize, at: 10, size: 2)
        put(spec.encryption, at: 12, size: 2)
        record.replaceSubrange(16..<20, with: Data("MOBI".utf8))
        put(headerLength, at: 20, size: 4)
        put(2, at: 24, size: 4)
        put(spec.encoding, at: 28, size: 4)
        put(spec.version, at: 36, size: 4)
        put(nameOffset, at: 84, size: 4)
        put(name.count, at: 88, size: 4)
        put(firstImage, at: 108, size: 4)
        put(huffmanCount > 0 ? huffmanRecord : 0, at: 112, size: 4)
        put(huffmanCount, at: 116, size: 4)
        put(spec.exth.isEmpty ? 0 : 0x40, at: 128, size: 4)
        put(spec.extraDataFlags, at: 0xF2, size: 2)
        record.append(exth)
        record.append(name)
        return record
    }
}
