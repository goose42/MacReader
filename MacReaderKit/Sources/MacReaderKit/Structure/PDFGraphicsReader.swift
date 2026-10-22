import CoreGraphics
import PDFKit

/// The shapes and pictures painted on one page, in PDF page coordinates (origin bottom-left).
struct PageGraphics: Equatable, Sendable {
    let pageIndex: Int
    let size: CGSize
    /// Rectangles that are filled or stroked.
    var rects: [CGRect] = []
    /// Frames of the images drawn on the page.
    var images: [CGRect] = []
}

/// Reads what a page paints by replaying its content stream, tracking only the transform and rectangle paths.
/// PDFKit exposes text but not drawing, so boxes and pictures have to come from here.
enum PDFGraphicsReader {
    static func graphics(in document: PDFDocument) -> [PageGraphics] {
        (0..<document.pageCount).map { index in
            guard let page = document.page(at: index), let ref = page.pageRef else {
                return PageGraphics(pageIndex: index, size: .zero)
            }
            let scan = Scan(images: imageNames(on: ref))
            let table = operatorTable()
            let scanner = CGPDFScannerCreate(
                CGPDFContentStreamCreateWithPage(ref), table, Unmanaged.passUnretained(scan).toOpaque())
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
            CGPDFOperatorTableRelease(table)
            return PageGraphics(
                pageIndex: index, size: page.bounds(for: .mediaBox).size, rects: scan.rects, images: scan.images)
        }
    }

    // MARK: - Scanning state

    private final class Scan {
        var ctm = CGAffineTransform.identity
        var saved: [CGAffineTransform] = []
        var path: [CGRect] = []
        /// Bounds of the subpath being drawn with move/line/curve operators.
        var subpath: CGRect?
        var rects: [CGRect] = []
        var images: [CGRect] = []
        let imageNames: Set<String>

        init(images: Set<String>) { imageNames = images }

        func extend(by points: [CGFloat]) {
            for index in stride(from: 0, to: points.count - 1, by: 2) {
                let point = CGPoint(x: points[index], y: points[index + 1]).applying(ctm)
                let single = CGRect(origin: point, size: .zero)
                subpath = subpath.map { $0.union(single) } ?? single
            }
        }

        func closeSubpath() {
            if let subpath { path.append(subpath) }
            subpath = nil
        }
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> Scan {
        Unmanaged<Scan>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values: [CGFloat] = []
        for _ in 0..<count {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
            values.insert(value, at: 0)
        }
        return values
    }

    private static func operatorTable() -> CGPDFOperatorTableRef {
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let scan = PDFGraphicsReader.state(info)
            scan.saved.append(scan.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let scan = PDFGraphicsReader.state(info)
            if let ctm = scan.saved.popLast() { scan.ctm = ctm }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let m = PDFGraphicsReader.numbers(scanner, 6) else { return }
            let scan = PDFGraphicsReader.state(info)
            scan.ctm = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]).concatenating(scan.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let r = PDFGraphicsReader.numbers(scanner, 4) else { return }
            let scan = PDFGraphicsReader.state(info)
            scan.closeSubpath()
            scan.path.append(CGRect(x: r[0], y: r[1], width: r[2], height: r[3]).applying(scan.ctm))
        }
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let p = PDFGraphicsReader.numbers(scanner, 2) else { return }
            let scan = PDFGraphicsReader.state(info)
            scan.closeSubpath()
            scan.extend(by: p)
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let p = PDFGraphicsReader.numbers(scanner, 2) else { return }
            PDFGraphicsReader.state(info).extend(by: p)
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            guard let p = PDFGraphicsReader.numbers(scanner, 6) else { return }
            PDFGraphicsReader.state(info).extend(by: p)
        }
        for curve in ["v", "y"] {
            CGPDFOperatorTableSetCallback(table, curve) { scanner, info in
                guard let p = PDFGraphicsReader.numbers(scanner, 4) else { return }
                PDFGraphicsReader.state(info).extend(by: p)
            }
        }
        for paint in ["f", "F", "f*", "B", "B*", "b", "b*", "S", "s"] {
            CGPDFOperatorTableSetCallback(table, paint) { _, info in
                let scan = PDFGraphicsReader.state(info)
                scan.closeSubpath()
                scan.rects += scan.path
                scan.path = []
            }
        }
        // Clipping paths end in `n` and must not count as shapes.
        CGPDFOperatorTableSetCallback(table, "n") { _, info in
            let scan = PDFGraphicsReader.state(info)
            scan.path = []
            scan.subpath = nil
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            let scan = PDFGraphicsReader.state(info)
            if scan.imageNames.contains(String(cString: name)) {
                scan.images.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(scan.ctm))
            }
        }
        return table
    }

    // MARK: - Resources

    /// Names of the image XObjects the page can draw.
    private static func imageNames(on page: CGPDFPage) -> Set<String> {
        Set(PDFPageResources.entries("XObject", on: page).compactMap { entry in
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(entry.dictionary, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image" else { return nil }
            return entry.name
        })
    }
}
