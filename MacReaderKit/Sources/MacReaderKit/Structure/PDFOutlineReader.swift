import PDFKit

/// Flattens a PDF's own bookmarks/outline into entries, depth-first, with 1-based levels.
enum PDFOutlineReader {
    static func entries(in document: PDFDocument) -> [OutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [OutlineEntry] = []
        func walk(_ outline: PDFOutline, level: Int) {
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                if let label = child.label, !label.isEmpty, let page = child.destination?.page {
                    entries.append(OutlineEntry(label: label, level: level, pageIndex: document.index(for: page)))
                }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 1)
        return entries
    }
}
