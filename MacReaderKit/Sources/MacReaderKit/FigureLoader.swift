import Foundation
import ImageIO

/// A picture decoded for display.
public struct LoadedFigure: @unchecked Sendable {
    /// Decoded no wider than was asked for.
    public let image: CGImage
    /// The picture's width in the file, whatever size it was decoded at, which gives its natural size on screen.
    public let pixelWidth: Int
}

/// Decodes pictures at the size they are shown, and keeps a bounded number of them. A book's pictures are stored as
/// files, often much larger than the column they are set in; reading one whole into memory just to draw it small is
/// what makes a picture-heavy book expensive to scroll through.
public final class FigureLoader: @unchecked Sendable {
    public static let shared = FigureLoader()

    private struct Entry {
        var figure: LoadedFigure
        var bytes: Int
    }

    private let byteLimit: Int
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    /// Keys from least to most recently used.
    private var order: [String] = []
    private var total = 0

    /// - Parameter byteLimit: how much decoded picture data to keep; the default is about a dozen full-width pictures.
    public init(byteLimit: Int = 64 * 1024 * 1024) {
        self.byteLimit = byteLimit
    }

    var cachedCount: Int { lock.withLock { entries.count } }
    var cachedBytes: Int { lock.withLock { total } }

    /// The picture at `url`, decoded no wider than `maxPixelWidth` (and never enlarged); nil if it can't be read.
    public func figure(at url: URL, maxPixelWidth: Int) -> LoadedFigure? {
        let key = "\(maxPixelWidth)|\(url.path)"
        if let cached = lock.withLock({ touch(key) }) { return cached }
        guard let figure = Self.decode(url, maxPixelWidth: maxPixelWidth) else { return nil }
        lock.withLock { insert(figure, for: key) }
        return figure
    }

    // MARK: Cache

    /// The cached picture for `key`, now the most recently used. Call with the lock held.
    private func touch(_ key: String) -> LoadedFigure? {
        guard let entry = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return entry.figure
    }

    /// Call with the lock held.
    private func insert(_ figure: LoadedFigure, for key: String) {
        if let old = entries[key] {
            total -= old.bytes
            order.removeAll { $0 == key }
        }
        let bytes = figure.image.bytesPerRow * figure.image.height
        entries[key] = Entry(figure: figure, bytes: bytes)
        order.append(key)
        total += bytes
        // The newest stays even if it alone is over the limit, since it is the one on screen.
        while total > byteLimit, order.count > 1 {
            let oldest = order.removeFirst()
            total -= entries.removeValue(forKey: oldest)?.bytes ?? 0
        }
    }

    // MARK: Decoding

    private static func decode(_ url: URL, maxPixelWidth: Int) -> LoadedFigure? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }

        // ImageIO limits the longer side, so scale that by how much the width must shrink.
        let longest = max(width, height)
        let limit = width <= maxPixelWidth ? longest : max(1, Int((Double(longest) * Double(maxPixelWidth) / Double(width)).rounded()))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return LoadedFigure(image: image, pixelWidth: width)
    }
}
