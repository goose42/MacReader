import Foundation

/// One visual line of a PDF page with the font size it was set in.
public struct TextLine: Equatable, Sendable {
    public let text: String
    public let fontSize: Double
    public let pageIndex: Int

    public init(text: String, fontSize: Double, pageIndex: Int) {
        self.text = text
        self.fontSize = fontSize
        self.pageIndex = pageIndex
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
