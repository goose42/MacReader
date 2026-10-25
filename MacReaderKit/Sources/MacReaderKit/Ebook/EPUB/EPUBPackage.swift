import Foundation

/// The package document (OPF) of a book: what it is called and who wrote it, which files it holds, and the order
/// they are read in.
struct EPUBPackage: Sendable {
    struct Item: Equatable, Sendable {
        var id: String
        /// Where the file is in the book, from its root.
        var path: String
        var mediaType: String
        var properties: Set<String>
    }

    var path: String
    var title: String?
    var authors: [String] = []
    var publisher: String?
    /// As written, possibly only a year.
    var date: String?
    var language: String?
    /// The blurb, with any markup removed.
    var summary: String?
    var identifier: String?
    /// The reading order: linear items as listed, then the ones the book marks `linear="no"`.
    var spine: [Item] = []
    var pageProgression: String?
    var navigationPath: String?
    var ncxPath: String?

    init(container: EPUBContainer) throws {
        let path = try container.packagePath()
        guard let root = try? XMLTree.parse(container.data(at: path)), root.name == "package" else {
            throw EPUBContainer.Failure.notAnEPUB
        }
        self.path = path

        var manifest: [String: Item] = [:]
        for element in root.child("manifest")?.children(named: "item") ?? [] {
            guard let id = element.attributes["id"], let href = element.attributes["href"],
                  let itemPath = EPUBPath.resolve(href, relativeTo: path)
            else { continue }
            let properties = Set((element.attributes["properties"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            manifest[id] = Item(
                id: id, path: itemPath, mediaType: element.attributes["media-type"] ?? "", properties: properties)
        }

        let spine = root.child("spine")
        var linear: [Item] = []
        var nonLinear: [Item] = []
        for reference in spine?.children(named: "itemref") ?? [] {
            guard let id = reference.attributes["idref"], let item = manifest[id] else { continue }
            if reference.attributes["linear"]?.lowercased() == "no" { nonLinear.append(item) } else { linear.append(item) }
        }
        self.spine = linear + nonLinear
        pageProgression = spine?.attributes["page-progression-direction"]
        navigationPath = manifest.values.first { $0.properties.contains("nav") }?.path
        ncxPath = spine?.attributes["toc"].flatMap { manifest[$0]?.path }
            ?? manifest.values.first { $0.mediaType == "application/x-dtbncx+xml" }?.path

        readMetadata(root.child("metadata"), uniqueIdentifier: root.attributes["unique-identifier"])
    }

    private mutating func readMetadata(_ metadata: XMLTreeNode?, uniqueIdentifier: String?) {
        guard let metadata else { return }

        // EPUB 3 qualifies an element with a separate <meta refines="#id" property="…">.
        var refinements: [String: [String: String]] = [:]
        for meta in metadata.children(named: "meta") {
            guard let target = meta.attributes["refines"], let property = meta.attributes["property"] else { continue }
            refinements[String(target.drop { $0 == "#" }), default: [:]][property] = meta.trimmedText
        }
        func refinement(_ element: XMLTreeNode, _ property: String) -> String? {
            element.attributes["id"].flatMap { refinements[$0]?[property] }
        }

        let titles = metadata.children(named: "title")
        let main = titles.first { refinement($0, "title-type") == "main" }
            ?? titles.first { refinement($0, "title-type") == nil } ?? titles.first
        title = main.flatMap { Self.clean($0.textContent) }

        let creators = metadata.children(named: "creator")
        let writers = creators.filter {
            let role = refinement($0, "role") ?? $0.attributes["role"]
            return role == nil || role == "aut"
        }
        var seen: Set<String> = []
        authors = (writers.isEmpty ? creators : writers).compactMap { Self.clean($0.textContent) }.filter { seen.insert($0).inserted }

        publisher = metadata.child("publisher").flatMap { Self.clean($0.textContent) }
        date = metadata.child("date").flatMap { Self.clean($0.textContent) }
        language = metadata.child("language").flatMap { Self.clean($0.textContent) }
        summary = metadata.child("description").flatMap { Self.clean(Self.removingMarkup(from: $0.textContent)) }
        let identifiers = metadata.children(named: "identifier")
        identifier = (identifiers.first { $0.attributes["id"] == uniqueIdentifier } ?? identifiers.first)
            .flatMap { Self.clean($0.textContent) }
    }

    /// Runs of whitespace collapsed to one space; nil if nothing is left.
    private static func clean(_ text: String) -> String? {
        let cleaned = text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Descriptions are often HTML written as text: paragraph tags become spaces, the rest vanish.
    private static func removingMarkup(from text: String) -> String {
        let spaced = text.replacing(/<\/?(?:p|br|div|li|h[1-6])\b[^>]*>/.ignoresCase(), with: " ")
        return HTMLEntities.decode(spaced.replacing(/<[^>]+>/, with: ""))
    }
}
