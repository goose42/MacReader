import Foundation

/// A user-selectable color setting: the app's automatic choice for that setting, or a custom sRGB color.
/// Its raw value (`automatic` or `#RRGGBB`) is what the app persists.
public enum ColorChoice: Equatable, Sendable, RawRepresentable {
    case automatic
    case custom(red: Double, green: Double, blue: Double)

    public init?(rawValue: String) {
        if rawValue == "automatic" {
            self = .automatic
            return
        }
        guard rawValue.hasPrefix("#"), rawValue.count == 7, rawValue.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(rawValue.dropFirst(), radix: 16)
        else { return nil }
        self = .custom(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    public var rawValue: String {
        switch self {
        case .automatic: "automatic"
        case .custom(let red, let green, let blue):
            String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
        }
    }

    private static func byte(_ component: Double) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}
