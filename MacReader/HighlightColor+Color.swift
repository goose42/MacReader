import AppKit
import MacReaderKit
import SwiftUI

extension HighlightColor {
    /// The tint drawn behind the current sentence.
    var fill: Color { color.opacity(0.25) }

    var color: Color {
        switch self {
        case .accent: .accentColor
        case .custom(let red, let green, let blue): Color(.sRGB, red: red, green: green, blue: blue)
        }
    }

    init(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
            self = .accent
            return
        }
        self = .custom(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}
