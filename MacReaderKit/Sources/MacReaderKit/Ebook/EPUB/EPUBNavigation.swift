import Foundation

/// A book's table of contents, from its EPUB 3 navigation document or, failing that, its EPUB 2 NCX.
struct EPUBNavigation: Sendable {
    struct Entry: Equatable, Sendable {
        var path: String
        var fragment: String?
        var title: String
        /// 0 for a top-level entry.
        var depth: Int
    }

    var entries: [Entry] = []

    /// Never fails: a book whose contents can't be read just has no entries, and reads from its own headings.
    static func load(from container: EPUBContainer, package: EPUBPackage) -> EPUBNavigation {
        if let path = package.navigationPath, let data = try? container.data(at: path),
           let document = try? XHTMLParser.parse(data) {
            let entries = navigationEntries(in: document.body, at: path)
            if !entries.isEmpty { return EPUBNavigation(entries: entries) }
        }
        if let path = package.ncxPath, let data = try? container.data(at: path), let root = try? XMLTree.parse(data) {
            return EPUBNavigation(entries: ncxEntries(in: root, at: path))
        }
        return EPUBNavigation()
    }

    /// The title the contents give the chapter in `path`: that of its first entry.
    func title(forChapterAt path: String) -> String? {
        entries.first { $0.path == path }?.title
    }

    // MARK: EPUB 3

    private static func navigationEntries(in body: HTMLNode, at base: String) -> [Entry] {
        let navs = body.all { $0.tag == "nav" }
        let toc = navs.first { types(of: $0).contains("toc") } ?? navs.first { $0.attributes["epub:type"] == nil }
        guard let list = toc?.first(where: { $0.tag == "ol" }) else { return [] }
        var entries: [Entry] = []
        collect(list, depth: 0, base: base, into: &entries)
        return entries
    }

    private static func types(of node: HTMLNode) -> Set<String> {
        Set((node.attributes["epub:type"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    }

    private static func collect(_ list: HTMLNode, depth: Int, base: String, into entries: inout [Entry]) {
        for item in list.children where item.tag == "li" {
            if let label = item.children.first(where: { $0.tag == "a" || $0.tag == "span" }) {
                let title = collapse(label.textContent)
                if label.tag == "a", let href = label.attributes["href"], let path = EPUBPath.resolve(href, relativeTo: base), !title.isEmpty {
                    entries.append(Entry(path: path, fragment: EPUBPath.fragment(of: href), title: title, depth: depth))
                }
            }
            if let nested = item.children.first(where: { $0.tag == "ol" }) {
                collect(nested, depth: depth + 1, base: base, into: &entries)
            }
        }
    }

    // MARK: EPUB 2

    private static func ncxEntries(in root: XMLTreeNode, at base: String) -> [Entry] {
        var entries: [Entry] = []
        func collect(_ points: [XMLTreeNode], depth: Int) {
            for point in points {
                let title = collapse(point.child("navLabel")?.child("text")?.textContent ?? "")
                if let source = point.child("content")?.attributes["src"], let path = EPUBPath.resolve(source, relativeTo: base), !title.isEmpty {
                    entries.append(Entry(path: path, fragment: EPUBPath.fragment(of: source), title: title, depth: depth))
                }
                collect(point.children(named: "navPoint"), depth: depth + 1)
            }
        }
        collect(root.child("navMap")?.children(named: "navPoint") ?? [], depth: 0)
        return entries
    }

    private static func collapse(_ text: String) -> String {
        text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// Whether a book is locked with DRM, which MacReader can't open. The font scrambling many publishers apply is not DRM.
enum EPUBProtection {
    private static let fontObfuscation: Set<String> = [
        "http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC",
    ]

    static func isProtected(_ container: EPUBContainer) -> Bool {
        if container.contains("META-INF/rights.xml") || container.contains("META-INF/sinf.xml") { return true }
        guard container.contains("META-INF/encryption.xml") else { return false }
        // A file that can't be read can't be vouched for.
        guard let data = try? container.data(at: "META-INF/encryption.xml"), let root = try? XMLTree.parse(data) else { return true }
        return root.descendants(named: "EncryptionMethod").contains { !fontObfuscation.contains($0.attributes["Algorithm"] ?? "") }
    }
}
