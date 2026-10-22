import AppKit
import PDFKit

/// Reads a PDF as visual lines annotated with font size, which is what lets us tell headings from body text.
enum PDFLineReader {
    static func lines(in document: PDFDocument) -> [TextLine] {
        var result: [TextLine] = []
        let fontCache = CodeLigatureDecoder.Cache()
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let attributed = page.attributedString else { continue }
            let ligatures = CodeLigatureDecoder.replacements(on: page, cache: fontCache)
            var location = 0
            for line in attributed.string.components(separatedBy: "\n") {
                defer { location += (line as NSString).length + 1 }
                let text = CodeLigatureDecoder.apply(ligatures, to: line.trimmingCharacters(in: .whitespaces))
                guard !text.isEmpty, location < attributed.length else { continue }
                let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
                let bounds = page.selection(for: NSRange(location: location, length: (line as NSString).length))?
                    .bounds(for: page) ?? .zero
                var textLine = TextLine(text: text, fontSize: Double(font?.pointSize ?? 0), pageIndex: pageIndex, bounds: bounds)
                textLine.sourceLocation = location + (line as NSString).length - (line.drop(while: { $0 == " " || $0 == "\t" }) as NSString).length
                result.append(textLine)
            }
        }
        return result
    }
}
