import Foundation

/// Builds small EPUBs for tests, either zipped or as an unpacked folder like the ones Apple Books keeps.
enum EPUBFixture {
    struct Chapter {
        var file: String
        var navTitle: String?
        var body: String
        var linear = true
    }

    struct Spec {
        var title = "A Test Book"
        var authors = ["Jane Author"]
        var publisher: String?
        var date: String?
        var language = "en"
        var description: String?
        /// "3.0" gets a navigation document, "2.0" an NCX.
        var version = "3.0"
        var rightToLeft = false
        var chapters: [Chapter] = []
        /// Files beyond the generated ones, by path inside the book.
        var extraFiles: [String: Data] = [:]
        /// Raw `<item/>` lines added to the manifest.
        var extraManifest = ""
        var encryptionXML: String?
        /// Replaces the generated navigation document or NCX.
        var navigationOverride: String?
        /// Rewrites the generated package document, for markup the spec has no field for.
        var editPackage: ((String) -> String)?
    }

    static let packagePath = "OEBPS/content.opf"

    static func xhtml(_ body: String, title: String = "Chapter", language: String = "en") -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)">
        <head><title>\(escape(title))</title></head>
        <body>\(body)</body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }

    static func files(_ spec: Spec) -> [(path: String, data: Data)] {
        let isThree = spec.version.hasPrefix("3")
        var files: [(String, Data)] = [
            ("META-INF/container.xml", Data("""
                <?xml version="1.0"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="\(packagePath)" media-type="application/oebps-package+xml"/></rootfiles>
                </container>
                """.utf8)),
            (packagePath, Data((spec.editPackage?(package(spec)) ?? package(spec)).utf8)),
        ]
        for chapter in spec.chapters {
            files.append(("OEBPS/\(chapter.file)", Data(xhtml(chapter.body, title: chapter.navTitle ?? "Chapter").utf8)))
        }
        if isThree {
            files.append(("OEBPS/nav.xhtml", Data((spec.navigationOverride ?? navigation(spec)).utf8)))
        } else {
            files.append(("OEBPS/toc.ncx", Data((spec.navigationOverride ?? ncx(spec)).utf8)))
        }
        if let encryption = spec.encryptionXML { files.append(("META-INF/encryption.xml", Data(encryption.utf8))) }
        for (path, data) in spec.extraFiles.sorted(by: { $0.key < $1.key }) { files.append((path, data)) }
        return files
    }

    /// The zipped book, with `mimetype` first and stored, as the format requires.
    static func archive(_ spec: Spec) -> Data {
        var entries: [ZipFixture.Entry] = [.init(name: "mimetype", data: Data("application/epub+zip".utf8))]
        for file in files(spec) { entries.append(.init(name: file.path, data: file.data, deflated: true)) }
        return ZipFixture.make(entries)
    }

    /// Writes the unpacked book to `directory`.
    static func write(_ spec: Spec, to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: directory.appendingPathComponent("mimetype"))
        for file in files(spec) {
            let url = directory.appendingPathComponent(file.path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url)
        }
    }

    static func writeArchive(_ spec: Spec) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        try archive(spec).write(to: url)
        return url
    }

    // MARK: Generated parts

    private static func package(_ spec: Spec) -> String {
        let isThree = spec.version.hasPrefix("3")
        var metadata = "<dc:identifier id=\"uid\">urn:uuid:0001</dc:identifier>\n"
        if isThree {
            metadata += "<dc:title id=\"t1\">\(escape(spec.title))</dc:title>\n<meta refines=\"#t1\" property=\"title-type\">main</meta>\n"
            for (index, author) in spec.authors.enumerated() {
                metadata += "<dc:creator id=\"c\(index)\">\(escape(author))</dc:creator>\n"
                metadata += "<meta refines=\"#c\(index)\" property=\"role\" scheme=\"marc:relators\">aut</meta>\n"
            }
        } else {
            metadata += "<dc:title>\(escape(spec.title))</dc:title>\n"
            for author in spec.authors { metadata += "<dc:creator opf:role=\"aut\">\(escape(author))</dc:creator>\n" }
        }
        metadata += "<dc:language>\(spec.language)</dc:language>\n"
        if let publisher = spec.publisher { metadata += "<dc:publisher>\(escape(publisher))</dc:publisher>\n" }
        if let date = spec.date { metadata += "<dc:date>\(date)</dc:date>\n" }
        if let description = spec.description { metadata += "<dc:description>\(escape(description))</dc:description>\n" }

        var manifest = isThree
            ? "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n"
            : "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n"
        var spine = ""
        for (index, chapter) in spec.chapters.enumerated() {
            manifest += "<item id=\"ch\(index)\" href=\"\(chapter.file)\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"ch\(index)\"\(chapter.linear ? "" : " linear=\"no\"")/>\n"
        }
        manifest += spec.extraManifest

        return """
            <?xml version="1.0" encoding="utf-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="\(spec.version)" unique-identifier="uid">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
            \(metadata)</metadata>
            <manifest>
            \(manifest)</manifest>
            <spine\(isThree ? "" : " toc=\"ncx\"")\(spec.rightToLeft ? " page-progression-direction=\"rtl\"" : "")>
            \(spine)</spine>
            </package>
            """
    }

    private static func navigation(_ spec: Spec) -> String {
        let items = spec.chapters.compactMap { chapter in
            chapter.navTitle.map { "<li><a href=\"\(chapter.file)\">\(escape($0))</a></li>" }
        }
        return xhtml("<nav epub:type=\"toc\"><ol>\(items.joined())</ol></nav>", title: "Contents")
    }

    private static func ncx(_ spec: Spec) -> String {
        let points = spec.chapters.enumerated().compactMap { index, chapter in
            chapter.navTitle.map {
                "<navPoint id=\"p\(index)\" playOrder=\"\(index + 1)\"><navLabel><text>\(escape($0))</text></navLabel><content src=\"\(chapter.file)\"/></navPoint>"
            }
        }
        return """
            <?xml version="1.0" encoding="utf-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
            <head/><docTitle><text>\(escape(spec.title))</text></docTitle>
            <navMap>\(points.joined())</navMap>
            </ncx>
            """
    }
}
