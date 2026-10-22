import CoreGraphics
import Foundation

/// One visual line of a PDF page with the font size it was set in.
public struct TextLine: Equatable, Sendable {
    public let text: String
    public let fontSize: Double
    public let pageIndex: Int
    /// Where the line sits on its page, in PDF page coordinates (origin bottom-left).
    public let bounds: CGRect
    /// The line's position in reading order; assigned when a document is built.
    var sequence = 0
    /// Where the line's text starts in its page's text, so individual characters can be located on the page.
    var sourceLocation: Int?

    public init(text: String, fontSize: Double, pageIndex: Int, bounds: CGRect = .zero) {
        self.text = text
        self.fontSize = fontSize
        self.pageIndex = pageIndex
        self.bounds = bounds
    }
}

enum FontStatistics {
    /// The font size covering the most characters, which is the document's body text.
    static func bodySize(of lines: [TextLine]) -> Double {
        var characters: [Double: Int] = [:]
        for line in lines { characters[line.fontSize, default: 0] += line.text.count }
        return characters.max { $0.value < $1.value }?.key ?? 0
    }
}
