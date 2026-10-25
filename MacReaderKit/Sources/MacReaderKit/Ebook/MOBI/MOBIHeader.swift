import Foundation

/// The first record of a Kindle book: the PalmDOC header, the MOBI header that follows it, and the EXTH block of
/// metadata after that.
struct MOBIHeader: Sendable {
    enum Failure: Error, Equatable { case notMOBI }

    // MARK: PalmDOC header

    /// 1 for none, 2 for PalmDOC, 17480 for Huffman with a dictionary.
    var compression: Int
    var textLength: Int
    var textRecordCount: Int
    var encryption: Int

    // MARK: MOBI header

    /// 1252 or 65001.
    var encoding: Int
    /// 6 for the old format and 8 for KF8.
    var version: Int
    var fullName: String
    /// The record of the first picture; the pictures a book refers to are numbered from it.
    var firstImageRecord: Int?
    var huffmanRecord: Int?
    var huffmanRecordCount: Int
    /// Which kinds of data trail each text record: bit 0 for a split multi-byte character, the others for entries.
    var extraDataFlags: Int

    // Indexes of a KF8 book, as record numbers.
    var ncxIndex: Int?
    var fragmentIndex: Int?
    var skeletonIndex: Int?
    var guideIndex: Int?
    var fdstIndex: Int?
    var fdstCount: Int

    /// The EXTH records by type; a type may repeat (a book can have several subjects).
    var exth: [Int: [Data]] = [:]

    var stringEncoding: String.Encoding { encoding == 65001 ? .utf8 : .windowsCP1252 }

    init(record: Data) throws {
        let record = Data(record)
        guard record.count >= 32, record[16..<20] == Data("MOBI".utf8) else { throw Failure.notMOBI }

        func number(_ offset: Int, _ size: Int) -> Int? {
            offset + size <= record.count ? (0..<size).reduce(0) { $0 << 8 | Int(record[offset + $1]) } : nil
        }
        /// An index or record number, where all ones means there is none.
        func optional(_ offset: Int) -> Int? {
            guard let value = number(offset, 4), value != 0xFFFF_FFFF else { return nil }
            return value
        }

        compression = number(0, 2) ?? 1
        textLength = number(4, 4) ?? 0
        textRecordCount = number(8, 2) ?? 0
        encryption = number(12, 2) ?? 0

        let headerLength = number(20, 4) ?? 0
        encoding = number(28, 4) ?? 1252
        version = number(36, 4) ?? 0
        let nameOffset = number(84, 4) ?? 0
        let nameLength = number(88, 4) ?? 0
        firstImageRecord = optional(108)
        huffmanRecordCount = number(116, 4) ?? 0
        huffmanRecord = huffmanRecordCount > 0 ? number(112, 4) : nil
        let exthFlags = number(128, 4) ?? 0

        extraDataFlags = headerLength >= 0xE4 && version >= 5 ? number(0xF2, 2) ?? 0 : 0
        if version >= 8 {
            fdstIndex = headerLength > 0xC4 ? optional(0xC0) : nil
            fdstCount = headerLength > 0xC4 ? number(0xC4, 4) ?? 0 : 0
            ncxIndex = optional(0xF4)
            fragmentIndex = optional(0xF8)
            skeletonIndex = optional(0xFC)
            guideIndex = optional(0x104)
        } else {
            fdstCount = 0
        }

        fullName = ""
        if nameLength > 0, nameOffset + nameLength <= record.count {
            fullName = String(data: record[nameOffset..<nameOffset + nameLength], encoding: stringEncoding)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let exthStart = 16 + headerLength
        if exthFlags & 0x40 != 0, exthStart + 12 <= record.count, record[exthStart..<exthStart + 4] == Data("EXTH".utf8) {
            var position = exthStart + 12
            for _ in 0..<(number(exthStart + 8, 4) ?? 0) {
                guard let type = number(position, 4), let length = number(position + 4, 4),
                      length >= 8, position + length <= record.count
                else { break }
                exth[type, default: []].append(Data(record[position + 8..<position + length]))
                position += length
            }
        }
    }

    // MARK: EXTH

    /// The first EXTH record of `type`, read as text.
    func string(_ type: Int) -> String? {
        exth[type]?.first.flatMap { String(data: $0, encoding: stringEncoding) }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func strings(_ type: Int) -> [String] {
        (exth[type] ?? []).compactMap { String(data: $0, encoding: stringEncoding)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The first EXTH record of `type`, read as a big-endian number.
    func integer(_ type: Int) -> Int? {
        guard let data = exth[type]?.first, (1...4).contains(data.count) else { return nil }
        return data.reduce(0) { $0 << 8 | Int($1) }
    }

    /// For a file that holds an old-format book followed by a KF8 one, the record where the KF8 book starts.
    var kf8Record: Int? { integer(121) }
}
