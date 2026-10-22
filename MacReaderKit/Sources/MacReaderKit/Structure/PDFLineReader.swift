import AppKit
import PDFKit

/// Reads a PDF as visual lines annotated with font size, which is what lets us tell headings from body text.
enum PDFLineReader {
    static func lines(in document: PDFDocument) -> [TextLine] {
        var result: [TextLine] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let attributed = page.attributedString else { continue }
            var location = 0
            for line in attributed.string.components(separatedBy: "\n") {
                defer { location += (line as NSString).length + 1 }
                let text = line.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, location < attributed.length else { continue }
                let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
                result.append(TextLine(text: text, fontSize: Double(font?.pointSize ?? 0), pageIndex: pageIndex))
            }
        }
        return result
    }
}
