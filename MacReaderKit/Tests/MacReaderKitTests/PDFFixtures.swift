import CoreGraphics
import CoreText
import Foundation
import PDFKit

enum PDFFixtures {
    /// Builds an in-memory PDF with one text string per page. Empty strings yield blank pages.
    static func makePDF(pages: [String], title: String? = nil) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [CFString: Any] = title.map { [kCGPDFContextTitle: $0] } ?? [:]
        let consumer = CGDataConsumer(data: data)!
        let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
        for text in pages {
            context.beginPDFPage(nil)
            if !text.isEmpty {
                let attributed = NSAttributedString(
                    string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)])
                let framesetter = CTFramesetterCreateWithAttributedString(attributed)
                let path = CGPath(rect: box.insetBy(dx: 72, dy: 72), transform: nil)
                CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    struct Run {
        let text: String
        let size: CGFloat
    }

    /// Builds a PDF where every run is drawn as its own line at the given font size, optionally with an outline of
    /// (label, zero-based page) top-level entries.
    static func makeStyledPDF(pages: [[Run]], title: String? = nil, outline: [(label: String, page: Int)] = []) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [CFString: Any] = title.map { [kCGPDFContextTitle: $0] } ?? [:]
        let consumer = CGDataConsumer(data: data)!
        let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
        for runs in pages {
            context.beginPDFPage(nil)
            var y: CGFloat = 720
            for run in runs {
                let font = CTFontCreateWithName("Helvetica" as CFString, run.size, nil)
                let attributed = NSAttributedString(
                    string: run.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                context.textPosition = CGPoint(x: 72, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
                y -= run.size * 1.6
            }
            context.endPDFPage()
        }
        if !outline.isEmpty {
            // PDFKit can't serialize outlines, so write them through Core Graphics (destinations are 1-based pages).
            let children = outline.map { [kCGPDFOutlineTitle: $0.label, kCGPDFOutlineDestination: $0.page + 1] as [CFString: Any] }
            CGPDFContextSetOutline(context, [kCGPDFOutlineChildren: children] as CFDictionary)
        }
        context.closePDF()
        return data as Data
    }
}
