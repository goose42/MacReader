import Foundation

/// The files of a KF8 book. Its markup is stored as skeletons (the frame of each file, up to the point where the body
/// goes) and fragments (what goes there), indexed separately, in the first of several flows; the others hold
/// stylesheets and SVG. A contents index names the files the chapters are in.
struct KF8Book: Sendable {
    enum Failure: Error, Equatable { case corrupt }

    struct Skeleton: Sendable {
        var fragmentCount: Int
        /// Where the skeleton is in the markup flow, and how long it is.
        var start: Int
        var length: Int
    }

    struct Fragment: Sendable {
        /// Where the fragment goes, counted in the finished file as if the skeleton started at 0 in the flow.
        var insertPosition: Int
        var length: Int
        /// The file (skeleton) it belongs to.
        var fileNumber = 0
    }

    struct Part: Sendable {
        /// An XHTML file, put back together.
        var data: Data
        /// What the book's contents call it, if they list it.
        var title: String?
    }

    let parts: [Part]
    /// Every flow; the first is the markup the parts were built from.
    let flows: [Data]

    init(book: MOBIBook) throws {
        let header = book.header
        guard let skeletonRecord = header.skeletonIndex, let fragmentRecord = header.fragmentIndex else { throw Failure.corrupt }
        let text = try book.text()
        flows = Self.flows(in: text, table: header.fdstIndex.flatMap { book.record($0) })

        let skeletons: [Skeleton]
        let fragments: [Fragment]
        do {
            let encoding = header.stringEncoding
            skeletons = try MOBIIndex(recordAt: skeletonRecord, encoding: encoding, record: book.record).entries.map { entry in
                guard let geometry = entry.tags[6], geometry.count >= 2 else { throw Failure.corrupt }
                return Skeleton(fragmentCount: entry.tags[1]?.first ?? 0, start: geometry[0], length: geometry[1])
            }
            fragments = try MOBIIndex(recordAt: fragmentRecord, encoding: encoding, record: book.record).entries.map { entry in
                guard let position = Int(String(decoding: entry.label, as: UTF8.self)), let geometry = entry.tags[6], geometry.count >= 2
                else { throw Failure.corrupt }
                return Fragment(insertPosition: position, length: geometry[1], fileNumber: entry.tags[3]?.first ?? 0)
            }
        } catch is MOBIIndex.Failure {
            throw Failure.corrupt
        }

        let assembled = try Self.assemble(flow: flows[0], skeletons: skeletons, fragments: fragments)
        let titles = header.ncxIndex.map { Self.titles(book: book, ncx: $0, fragments: fragments) } ?? [:]
        parts = assembled.enumerated().map { Part(data: $1, title: titles[$0]) }
    }

    // MARK: Flows

    /// The text cut into the flows the FDST record lists; one flow if the book has no such record.
    private static func flows(in text: Data, table: Data?) -> [Data] {
        guard let table, table.count >= 12, table.prefix(4) == Data("FDST".utf8) else { return [text] }
        func integer(_ offset: Int) -> Int? {
            offset + 4 <= table.count ? (0..<4).reduce(0) { $0 << 8 | Int(table[table.startIndex + offset + $1]) } : nil
        }
        guard let count = integer(8), count > 0, 12 + 8 * count <= table.count else { return [text] }
        let starts = (0..<count).compactMap { integer(12 + 8 * $0) }
        guard starts.first == 0, starts == starts.sorted(), starts.last.map({ $0 <= text.count }) == true else { return [text] }

        return starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : text.count
            return Data(text[text.startIndex + starts[index]..<text.startIndex + end])
        }
    }

    // MARK: Putting the files together

    /// Each skeleton, with the fragments that follow it in the flow put in where the fragment table says. The fragments
    /// of one file come in order, and their positions count the ones already put in.
    static func assemble(flow: Data, skeletons: [Skeleton], fragments: [Fragment]) throws -> [Data] {
        let bytes = [UInt8](flow)
        var parts: [Data] = []
        var next = 0
        for skeleton in skeletons {
            guard skeleton.fragmentCount >= 0, skeleton.start >= 0, skeleton.length >= 0,
                  skeleton.start + skeleton.length <= bytes.count
            else { throw Failure.corrupt }
            var file = Array(bytes[skeleton.start..<skeleton.start + skeleton.length])
            var source = skeleton.start + skeleton.length

            for _ in 0..<skeleton.fragmentCount {
                guard next < fragments.count else { throw Failure.corrupt }
                let fragment = fragments[next]
                next += 1
                guard fragment.length >= 0, source + fragment.length <= bytes.count else { throw Failure.corrupt }
                let position = fragment.insertPosition - skeleton.start
                guard position >= 0, position <= file.count else { throw Failure.corrupt }

                file.insert(contentsOf: bytes[source..<source + fragment.length], at: outsideTag(position, in: file))
                source += fragment.length
            }
            parts.append(Data(file))
        }
        return parts
    }

    /// Some books have a fragment table that points into the middle of a tag; the fragment belongs after it.
    private static func outsideTag(_ position: Int, in bytes: [UInt8]) -> Int {
        var index = position - 1
        while index >= 0 {
            if bytes[index] == UInt8(ascii: ">") { return position }
            if bytes[index] == UInt8(ascii: "<") { break }
            index -= 1
        }
        guard index >= 0, let close = bytes[position...].firstIndex(of: UInt8(ascii: ">")) else { return position }
        return close + 1
    }

    // MARK: Contents

    /// The title the contents give each file: that of the first entry that points into it.
    private static func titles(book: MOBIBook, ncx: Int, fragments: [Fragment]) -> [Int: String] {
        guard let index = try? MOBIIndex(recordAt: ncx, encoding: book.header.stringEncoding, record: book.record) else { return [:] }
        var titles: [Int: String] = [:]
        for entry in index.entries {
            guard let offset = entry.tags[3]?.first, let label = index.strings[offset].flatMap(EbookText.clean),
                  let fragment = entry.tags[6]?.first, fragments.indices.contains(fragment)
            else { continue }
            let file = fragments[fragment].fileNumber
            if titles[file] == nil { titles[file] = label }
        }
        return titles
    }

    // MARK: Pictures

    /// The address the shared reader uses for a picture (`mobi-image:<n>`), for a source as a KF8 book writes it:
    /// `kindle:embed:0001?mime=image/jpeg`, or a `kindle:flow:` that is an SVG drawing one.
    func pictureAddress(for source: String) -> String? {
        if let number = Self.number(after: "kindle:embed:", in: source) { return "\(MOBI6Markup.imageScheme)\(number)" }
        guard let flow = Self.number(after: "kindle:flow:", in: source), flows.indices.contains(flow),
              let number = Self.number(after: "kindle:embed:", in: String(decoding: flows[flow], as: UTF8.self))
        else { return nil }
        return "\(MOBI6Markup.imageScheme)\(number)"
    }

    /// The base-32 number after `prefix`.
    private static func number(after prefix: String, in text: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let digits = text[range.upperBound...].prefix { $0.isASCII && ($0.isNumber || $0.isLetter) }
        return Int(digits, radix: 32)
    }
}
