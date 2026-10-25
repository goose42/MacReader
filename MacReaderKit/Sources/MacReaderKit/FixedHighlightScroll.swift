import Foundation

/// Where to scroll so the current sentence stays a fixed number of lines below the top of the reader.
public enum FixedHighlightScroll {
    public static let lineRange = 1...10
    public static let defaultLines = 3

    /// The content offset that puts the sentence `lines` lines below the top of the visible area, clamped so the page
    /// never scrolls before its start or past its end. `sentenceTop` is measured from the top of the visible area.
    public static func targetOffset(
        sentenceTop: Double, lineHeight: Double, lines: Int,
        currentOffset: Double, viewportHeight: Double, contentHeight: Double
    ) -> Double {
        let gap = Double(min(max(lines, lineRange.lowerBound), lineRange.upperBound)) * lineHeight
        let wanted = currentOffset + sentenceTop - gap
        return min(max(wanted, 0), max(0, contentHeight - viewportHeight))
    }
}
