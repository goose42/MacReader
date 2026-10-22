import CoreGraphics
import Testing
@testable import MacReaderKit

struct BoxDetectorTests {
    private let page = CGSize(width: 612, height: 792)

    @Test func keepsAContentSizedRectangle() {
        let box = CGRect(x: 72, y: 500, width: 400, height: 80)
        #expect(BoxDetector.boxes(from: [box], pageSize: page) == [box])
    }

    @Test func dropsPageBackgroundsRulesAndSpecks() {
        let background = CGRect(x: 0, y: 0, width: 612, height: 792)
        let rule = CGRect(x: 72, y: 400, width: 400, height: 1)
        let speck = CGRect(x: 72, y: 300, width: 8, height: 8)
        #expect(BoxDetector.boxes(from: [background, rule, speck], pageSize: page).isEmpty)
    }

    @Test func mergesTouchingFillsIntoOneBox() {
        // A code block painted as one fill per line, with hairline gaps between them.
        let lines = (0..<3).map { CGRect(x: 72, y: 500 + CGFloat($0) * 20.5, width: 400, height: 20) }
        let merged = BoxDetector.boxes(from: lines, pageSize: page)
        #expect(merged == [CGRect(x: 72, y: 500, width: 400, height: 61)])
    }

    @Test func keepsSeparatedBoxesApart() {
        let top = CGRect(x: 72, y: 600, width: 400, height: 60)
        let bottom = CGRect(x: 72, y: 300, width: 400, height: 60)
        #expect(BoxDetector.boxes(from: [bottom, top], pageSize: page).count == 2)
    }

    @Test func absorbsRectanglesNestedInsideABox() {
        let outer = CGRect(x: 72, y: 500, width: 400, height: 120)
        let inner = CGRect(x: 90, y: 520, width: 200, height: 40)
        #expect(BoxDetector.boxes(from: [outer, inner], pageSize: page) == [outer])
    }

    @Test func figuresDropTinyImagesAndFullPageScans() {
        let logo = CGRect(x: 72, y: 700, width: 24, height: 24)
        let scan = CGRect(x: 0, y: 0, width: 612, height: 792)
        let photo = CGRect(x: 72, y: 300, width: 300, height: 200)
        #expect(BoxDetector.figureFrames(from: [logo, scan, photo], pageSize: page) == [photo])
    }

    @Test func mergesShortPerLineFillsThatAreTallEnoughTogether() {
        let lines = (0..<3).map { CGRect(x: 72, y: 500 + CGFloat($0) * 10, width: 300, height: 10) }
        #expect(BoxDetector.boxes(from: lines, pageSize: page) == [CGRect(x: 72, y: 500, width: 300, height: 30)])
    }

    @Test func doesNotTurnATablesBorderRulesIntoABox() {
        let rules = [500, 520, 540, 560].map { CGRect(x: 72, y: CGFloat($0), width: 300, height: 1.5) }
            + [72, 372].map { CGRect(x: CGFloat($0), y: 500, width: 1.5, height: 61.5) }
        #expect(BoxDetector.boxes(from: rules, pageSize: page).isEmpty)
    }
}
