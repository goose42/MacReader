import AppKit
import MacReaderKit
import SwiftUI

extension ColorChoice {
    /// The chosen color, or `automatic` when the setting is left on its default.
    func color(automatic: Color) -> Color {
        switch self {
        case .automatic: automatic
        case .custom(let red, let green, let blue): Color(.sRGB, red: red, green: green, blue: blue)
        }
    }

    init(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
            self = .automatic
            return
        }
        self = .custom(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}

extension ColorChoice {
    /// The tint drawn behind the current sentence; the system accent color unless customized.
    var highlightFill: Color { color(automatic: .accentColor).opacity(0.25) }

    /// The color of text outside the current sentence; the system secondary color unless customized.
    var dimmedText: Color { color(automatic: .secondary) }
}
