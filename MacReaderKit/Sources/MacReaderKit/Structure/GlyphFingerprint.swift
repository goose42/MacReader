import CoreGraphics
import CoreText
import Foundation

/// A coarse bitmap of a glyph's outline, so a glyph can be recognised by shape when a font names nothing.
///
/// Outlines are drawn on a fixed frame in font units (so a ligature's overhang to the left is part of its shape) and
/// reduced to a grid of blocks.
struct GlyphFingerprint: Equatable, Sendable {
    static let columns = 45
    static let rows = 16

    private static let pointSize: CGFloat = 100
    private static let block = 4
    private static let pixelsPerUnit: CGFloat = 0.5
    private static let origin = CGPoint(x: 300, y: 30)

    private let bits: [Bool]

    init?(glyph: CGGlyph, in font: CTFont) {
        let width = Self.columns * Self.block, height = Self.rows * Self.block
        let unit = Self.pointSize / CTFontGetSize(font)
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.isEmpty,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }

        context.scaleBy(x: Self.pixelsPerUnit * unit, y: Self.pixelsPerUnit * unit)
        context.translateBy(x: Self.origin.x / unit, y: Self.origin.y / unit)
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path)
        context.fillPath()

        var bits: [Bool] = []
        for row in 0..<Self.rows {
            for column in 0..<Self.columns {
                var covered = 0
                for y in 0..<Self.block {
                    for x in 0..<Self.block where pixels[(row * Self.block + y) * width + column * Self.block + x] > 127 {
                        covered += 1
                    }
                }
                bits.append(covered * 4 >= Self.block * Self.block)
            }
        }
        self.bits = bits
    }

    init?(hex: String) {
        let digits = Array(hex)
        guard digits.count * 4 >= Self.columns * Self.rows else { return nil }
        var bits: [Bool] = []
        for digit in digits {
            guard let value = digit.hexDigitValue else { return nil }
            for shift in (0..<4).reversed() { bits.append(value >> shift & 1 == 1) }
        }
        self.bits = Array(bits.prefix(Self.columns * Self.rows))
    }

    var hex: String {
        stride(from: 0, to: bits.count, by: 4).map { start in
            let value = (0..<4).reduce(0) { $0 << 1 | (start + $1 < bits.count && bits[start + $1] ? 1 : 0) }
            return String(value, radix: 16)
        }.joined()
    }

    /// Intersection over union of the two shapes: 1 for identical outlines, near 0 for unrelated ones.
    func similarity(to other: GlyphFingerprint) -> Double {
        var both = 0, either = 0
        for (a, b) in zip(bits, other.bits) {
            if a && b { both += 1 }
            if a || b { either += 1 }
        }
        return either == 0 ? 0 : Double(both) / Double(either)
    }
}
