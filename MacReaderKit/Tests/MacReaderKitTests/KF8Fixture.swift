import Foundation

/// Builds KF8 books for tests: the markup is split into skeletons (the frame of each file) and fragments (what goes
/// inside), with indexes for both, a table of flows, and an index of the contents.
enum KF8Fixture {
    struct Part {
        /// The file up to the point where its fragments are inserted.
        var prefix: String
        var suffix = "</body></html>"
        var fragments: [String] = []
        /// What the book's contents call this file.
        var title: String?

        init(prefix: String = "<html><head><title>t</title></head><body>", suffix: String = "</body></html>", fragments: [String] = [], title: String? = nil) {
            self.prefix = prefix
            self.suffix = suffix
            self.fragments = fragments
            self.title = title
        }
    }

    struct Spec {
        var title = "A KF8 Book"
        var parts: [Part] = []
        /// Flows after the markup: stylesheets, or SVG that pictures are drawn in.
        var flows: [String] = []
        var images: [Data] = []
        var exth: [(type: Int, value: Data)] = []
        var encryption = 0
        var compression = 2
        var recordSize = 4096
        var extraDataFlags = 0
        /// An old-format book that the file holds before this one.
        var joint: MOBIFixture.Spec?
    }

    static func build(_ spec: Spec) -> Data {
        if let old = spec.joint {
            var old = old
            // The old book points at where this one begins: after its own records and a boundary record.
            var records = MOBIFixture.records(old)
            let start = records.count + 1
            old.exth.append(MOBIFixture.exth(121, number: start))
            records = MOBIFixture.records(old)
            records.append(Data("BOUNDARY".utf8))
            records += self.records(spec)
            return PalmFixture.database(name: "Joint_Book", type: "BOOK", creator: "MOBI", records: records)
        }
        return PalmFixture.database(name: "KF8_Book", type: "BOOK", creator: "MOBI", records: records(spec))
    }

    static func records(_ spec: Spec) -> [Data] {
        // The markup flow: each skeleton followed by its fragments, which are inserted into it when it is read.
        var markup = Data()
        var skeletons: [INDXFixture.Entry] = []
        var fragments: [INDXFixture.Entry] = []
        var firstFragment: [Int] = []
        for (number, part) in spec.parts.enumerated() {
            let skeleton = Data((part.prefix + part.suffix).utf8)
            let start = markup.count
            skeletons.append(.init(
                label: String(format: "SKEL%010d", number), tags: [1: [part.fragments.count], 6: [start, skeleton.count]]))
            markup.append(skeleton)

            firstFragment.append(fragments.count)
            var inserted = 0
            for (sequence, fragment) in part.fragments.enumerated() {
                let data = Data(fragment.utf8)
                fragments.append(.init(
                    label: String(format: "%010d", start + part.prefix.utf8.count + inserted),
                    tags: [3: [number], 4: [sequence], 6: [0, data.count]]))
                inserted += data.count
                markup.append(data)
            }
        }

        let flows = [markup] + spec.flows.map { Data($0.utf8) }
        let rawText = flows.reduce(Data(), +)
        var records: [Data] = [Data()]
        records += MOBIFixture.textRecords(rawText, size: spec.recordSize, compression: spec.compression, extraDataFlags: spec.extraDataFlags)
        let textRecordCount = records.count - 1

        var indexes = MOBIFixture.KF8Indexes()
        let fragmentIndex = INDXFixture.build(tags: [
            .init(number: 2, valuesPerEntry: 1, mask: 1), .init(number: 3, valuesPerEntry: 1, mask: 2),
            .init(number: 4, valuesPerEntry: 1, mask: 4), .init(number: 6, valuesPerEntry: 2, mask: 8),
            .init(number: 0, valuesPerEntry: 0, mask: 0, isEnd: true),
        ], entries: fragments)
        indexes.fragment = records.count
        records += fragmentIndex.records

        let skeletonIndex = INDXFixture.build(tags: [
            .init(number: 1, valuesPerEntry: 1, mask: 3), .init(number: 6, valuesPerEntry: 2, mask: 12),
            .init(number: 0, valuesPerEntry: 0, mask: 0, isEnd: true),
        ], entries: skeletons)
        indexes.skeleton = records.count
        records += skeletonIndex.records

        let titled = spec.parts.enumerated().filter { $0.element.title != nil }
        if !titled.isEmpty {
            let titles = titled.map { $0.element.title! }
            var offsets: [Int] = []
            var position = 0
            for title in titles {
                offsets.append(position)
                position += INDXFixture.variableWidth(Data(title.utf8).count).count + Data(title.utf8).count
            }
            let entries = titled.enumerated().map { index, item in
                INDXFixture.Entry(label: String(format: "%02X", index), tags: [
                    1: [0], 2: [0], 3: [offsets[index]], 4: [0], 6: [firstFragment[item.offset], 0],
                ])
            }
            let ncx = INDXFixture.build(tags: [
                .init(number: 1, valuesPerEntry: 1, mask: 1), .init(number: 2, valuesPerEntry: 1, mask: 2),
                .init(number: 3, valuesPerEntry: 1, mask: 4), .init(number: 4, valuesPerEntry: 1, mask: 8),
                .init(number: 5, valuesPerEntry: 1, mask: 16), .init(number: 21, valuesPerEntry: 1, mask: 32),
                .init(number: 22, valuesPerEntry: 1, mask: 64), .init(number: 23, valuesPerEntry: 1, mask: 128),
                .init(number: 0, valuesPerEntry: 0, mask: 0, isEnd: true),
                .init(number: 6, valuesPerEntry: 2, mask: 1), .init(number: 0, valuesPerEntry: 0, mask: 0, isEnd: true),
            ], controlBytes: 2, entries: entries, strings: titles)
            indexes.ncx = records.count
            records += ncx.records
        }

        let firstImage = records.count
        records += spec.images

        var table = Data("FDST".utf8)
        table.append(be32: 12)
        table.append(be32: flows.count)
        var start = 0
        for flow in flows {
            table.append(be32: start)
            table.append(be32: start + flow.count)
            start += flow.count
        }
        indexes.fdst = records.count
        indexes.fdstCount = flows.count
        records.append(table)
        records.append(Data("EOF".utf8))

        var old = MOBIFixture.Spec(title: spec.title)
        old.compression = spec.compression
        old.version = 8
        old.encryption = spec.encryption
        old.extraDataFlags = spec.extraDataFlags
        old.recordSize = spec.recordSize
        old.exth = spec.exth
        records[0] = MOBIFixture.firstRecord(
            old, textRecordCount: textRecordCount, textLength: rawText.count, huffmanRecord: 0, huffmanCount: 0,
            firstImage: spec.images.isEmpty ? 0xFFFF_FFFF : firstImage, kf8: indexes)
        return records
    }
}
