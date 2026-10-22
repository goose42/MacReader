import Foundation

/// Reads the code-to-glyph table PDF generators put in embedded simple TrueType fonts.
enum TrueTypeCMap {
    /// Glyph ids by character code, from the Macintosh (platform 1) `cmap` subtable. Empty for anything unreadable.
    static func glyphs(in font: Data) -> [Int: Int] {
        let bytes = [UInt8](font)
        func u16(_ offset: Int) -> Int? {
            offset >= 0 && offset + 2 <= bytes.count ? Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) : nil
        }
        func u32(_ offset: Int) -> Int? {
            guard let high = u16(offset), let low = u16(offset + 2) else { return nil }
            return high << 16 | low
        }

        guard let tableCount = u16(4), let cmap = (0..<tableCount).lazy.compactMap({ index -> Int? in
            let record = 12 + 16 * index
            guard record + 12 <= bytes.count, Array(bytes[record..<record + 4]) == Array("cmap".utf8) else { return nil }
            return u32(record + 8)
        }).first, let subtableCount = u16(cmap + 2) else { return [:] }

        for index in 0..<subtableCount {
            guard let platform = u16(cmap + 4 + 8 * index), let encoding = u16(cmap + 6 + 8 * index),
                  let offset = u32(cmap + 8 + 8 * index), platform == 1, encoding == 0 else { continue }
            let table = cmap + offset
            var glyphs: [Int: Int] = [:]
            switch u16(table) {
            case 0:
                for code in 0..<256 {
                    if table + 6 + code < bytes.count, bytes[table + 6 + code] != 0 { glyphs[code] = Int(bytes[table + 6 + code]) }
                }
            case 6:
                guard let first = u16(table + 6), let count = u16(table + 8) else { return [:] }
                for entry in 0..<count {
                    if let glyph = u16(table + 10 + 2 * entry), glyph != 0 { glyphs[first + entry] = glyph }
                }
            default:
                return [:]
            }
            return glyphs
        }
        return [:]
    }
}
