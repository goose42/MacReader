import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Renders a region of a PDF page to PNG, so pictures (and the vector art around them) can be shown in the reader.
enum FigureRenderer {
    private static let scale: CGFloat = 2

    static func png(of rect: CGRect, on page: PDFPage) -> Data? {
        guard let pageRef = page.pageRef, rect.width > 0, rect.height > 0,
              let context = CGContext(
                  data: nil, width: Int((rect.width * scale).rounded(.up)), height: Int((rect.height * scale).rounded(.up)),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.drawPDFPage(pageRef)

        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
