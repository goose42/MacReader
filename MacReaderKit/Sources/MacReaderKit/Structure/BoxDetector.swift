import CoreGraphics

/// Turns the rectangles a page paints into the boxes a reader would see: backgrounds, rules and specks are dropped,
/// and fills that touch or overlap are merged.
enum BoxDetector {
    private static let minWidth: CGFloat = 60
    private static let minHeight: CGFloat = 14
    /// Anything thinner than this is a rule or border line, not the edge of a box.
    private static let minThickness: CGFloat = 3
    private static let maxPageCoverage: CGFloat = 0.85
    /// Fills closer than this read as one block (a code box painted a line at a time leaves hairline gaps).
    private static let mergeGap: CGFloat = 3

    private static let minFigureSide: CGFloat = 40

    /// Frames worth showing as figures: icons and bullets are dropped, as are images that are the page itself.
    static func figureFrames(from images: [CGRect], pageSize: CGSize) -> [CGRect] {
        let pageArea = pageSize.width * pageSize.height
        return images.map(\.standardized).filter { frame in
            frame.width >= minFigureSide && frame.height >= minFigureSide && frame.width * frame.height < pageArea * maxPageCoverage
        }
    }

    /// Boxes in reading order, top of the page first.
    static func boxes(from rects: [CGRect], pageSize: CGSize) -> [CGRect] {
        let pageArea = pageSize.width * pageSize.height
        var boxes = rects.map(\.standardized).filter { rect in
            min(rect.width, rect.height) >= minThickness && rect.width * rect.height < pageArea * maxPageCoverage
        }

        var merged = true
        while merged {
            merged = false
            outer: for i in boxes.indices {
                for j in boxes.indices where j > i {
                    if boxes[i].insetBy(dx: -mergeGap / 2, dy: -mergeGap / 2)
                        .intersects(boxes[j].insetBy(dx: -mergeGap / 2, dy: -mergeGap / 2)) {
                        boxes[i] = boxes[i].union(boxes[j])
                        boxes.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        // Size is judged after merging, since a box painted one short line at a time is only tall as a whole.
        boxes = boxes.filter { $0.width >= minWidth && $0.height >= minHeight }
        return boxes.sorted { $0.maxY != $1.maxY ? $0.maxY > $1.maxY : $0.minX < $1.minX }
    }
}
