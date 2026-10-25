import Foundation

/// A Palm database, the container under every MOBI, AZW and PRC book: a short header, a list of record offsets and
/// the records themselves.
struct PalmDatabase: Sendable {
    enum Failure: Error, Equatable { case notAPalmDatabase }

    private let bytes: Data
    private let offsets: [Int]

    /// The database's name, which for a book is a mangled form of its title.
    let name: String
    /// Four characters each: `BOOK` and `MOBI` for a Kindle book, `TEXt` and `REAd` for a plain PalmDOC.
    let type: String
    let creator: String

    var recordCount: Int { offsets.count }

    var isMobipocket: Bool { type == "BOOK" && creator == "MOBI" }

    init(data: Data) throws {
        let data = Data(data)
        guard data.count >= 78 else { throw Failure.notAPalmDatabase }
        let count = Int(data[76]) << 8 | Int(data[77])
        guard 78 + 8 * count <= data.count else { throw Failure.notAPalmDatabase }

        var offsets: [Int] = []
        var previous = 0
        for index in 0..<count {
            let base = 78 + 8 * index
            let offset = (0..<4).reduce(0) { $0 << 8 | Int(data[base + $1]) }
            guard offset >= previous, offset <= data.count else { throw Failure.notAPalmDatabase }
            offsets.append(offset)
            previous = offset
        }

        bytes = data
        self.offsets = offsets
        name = String(decoding: data[0..<32].prefix { $0 != 0 }, as: UTF8.self)
        type = String(decoding: data[60..<64], as: UTF8.self)
        creator = String(decoding: data[64..<68], as: UTF8.self)
    }

    /// The bytes of record `index`, which run to the start of the next record or the end of the file.
    func record(at index: Int) -> Data? {
        view(ofRecord: index).map { Data($0) }
    }

    /// The same bytes as `record(at:)`, as a window onto the file's own storage rather than a copy. Its indices don't
    /// start at zero, so index it through `startIndex`; it keeps the whole file alive for as long as it is held, which
    /// is cheap when the file is memory-mapped. For records read once and written out, such as pictures.
    func view(ofRecord index: Int) -> Data? {
        guard offsets.indices.contains(index) else { return nil }
        let end = index + 1 < offsets.count ? offsets[index + 1] : bytes.count
        return bytes[offsets[index]..<end]
    }
}
