import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Usage: generate <source image> <AppIcon.appiconset directory>
// Crops the icon artwork out of its background and writes the macOS icon set.

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate <source image> <appiconset dir>\n".utf8))
    exit(2)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read \(sourceURL.path)")
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let premultiplied = CGImageAlphaInfo.premultipliedLast.rawValue

func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: colorSpace, bitmapInfo: premultiplied)!
}

// MARK: Find the artwork

let width = image.width
let height = image.height
let scan = makeContext(width: width, height: height)
scan.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = scan.data!.assumingMemoryBound(to: UInt8.self)
let rowBytes = scan.bytesPerRow

func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let offset = y * rowBytes + x * 4
    return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
}

let background = pixel(4, 4)
func isArtwork(_ x: Int, _ y: Int, threshold: Int = 60) -> Bool {
    let p = pixel(x, y)
    return abs(p.0 - background.0) + abs(p.1 - background.1) + abs(p.2 - background.2) > threshold
}

// The drop shadow under the icon is faint, so the bottom edge uses a stricter threshold.
// Scan inward along the centre lines so corner debris (e.g. a download glyph) is ignored.
let midY = height / 2
guard let left = (0..<width).first(where: { isArtwork($0, midY) }),
      let right = (0..<width).reversed().first(where: { isArtwork($0, midY) }) else {
    fatalError("No artwork found")
}
let midX = (left + right) / 2
guard let top = (0..<height).first(where: { isArtwork(midX, $0) }),
      let bottom = (0..<height).reversed().first(where: { isArtwork(midX, $0, threshold: 200) }) else {
    fatalError("No artwork found")
}

// Inset a few pixels so the source's anti-aliased edge doesn't leave a halo.
let inset = 3
let crop = CGRect(x: left + inset, y: top + inset,
                  width: right - left + 1 - 2 * inset, height: bottom - top + 1 - 2 * inset)
guard let artwork = image.cropping(to: crop) else { fatalError("Crop failed") }
print("Artwork bounds: \(crop)")

// MARK: Compose the 1024 master (Apple's icon grid: 824pt body, 100pt margin)

let masterSize = 1024
let bodySize: CGFloat = 824
let margin = (CGFloat(masterSize) - bodySize) / 2
let master = makeContext(width: masterSize, height: masterSize)
master.interpolationQuality = .high
let body = CGRect(x: margin, y: margin, width: bodySize, height: bodySize)
let radius = bodySize * 0.2237
master.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
master.clip()
master.draw(artwork, in: body)
let masterImage = master.makeImage()!

// MARK: Write the icon set

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(url.path)") }
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var entries: [String] = []
for slot in slots {
    let pixelSize = slot.points * slot.scale
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    let context = makeContext(width: pixelSize, height: pixelSize)
    context.interpolationQuality = .high
    context.draw(masterImage, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    writePNG(context.makeImage()!, to: outputDirectory.appendingPathComponent(name))
    entries.append("""
        {
          "filename" : "\(name)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)x",
          "size" : "\(slot.points)x\(slot.points)"
        }
    """)
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
