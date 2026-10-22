import Foundation

/// How wide the reader sets its text column: a comfortable measure, or the whole window.
public enum ReaderColumnWidth: String, CaseIterable, Identifiable, Sendable {
    case narrow
    case wide

    public var id: Self { self }

    public var title: String {
        switch self {
        case .narrow: "Narrow"
        case .wide: "Wide"
        }
    }

    public var systemImage: String {
        switch self {
        case .narrow: "arrow.right.and.line.vertical.and.arrow.left"
        case .wide: "arrow.left.and.right"
        }
    }

    /// The widest the column may grow, or nil to fill the window.
    public var maxWidth: CGFloat? {
        switch self {
        case .narrow: 680
        case .wide: nil
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .narrow: 32
        case .wide: 48
        }
    }
}
