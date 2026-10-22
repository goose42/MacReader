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

    /// Frames used by `makeVisualPDF`, in PDF page coordinates (origin bottom-left).
    static let visualBox = CGRect(x: 60, y: 560, width: 480, height: 100)
    static let visualImage = CGRect(x: 72, y: 380, width: 200, height: 100)

    /// One page: a line of text, a grey box holding a line of text, a line after it, and a drawn image.
    static func makeVisualPDF() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        func draw(_ text: String, at point: CGPoint) {
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = point
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        draw("Before the box", at: CGPoint(x: 72, y: 720))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(visualBox)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        draw("Boxed note", at: CGPoint(x: 80, y: 620))
        draw("After the box", at: CGPoint(x: 72, y: 520))

        let bitmap = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        context.draw(bitmap.makeImage()!, in: visualImage)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// One page with a grey rounded-rectangle fill, which PDF writes as curves rather than a `re` rectangle.
    static func makeRoundedBoxPDF(_ rect: CGRect) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
