import Foundation

/// A color setting with its own value for light and dark appearance.
/// Its raw value is `light|dark`; a single `ColorChoice` value saved by an earlier version applies to both.
public struct AppearanceColor: Equatable, Sendable, RawRepresentable {
    public var light: ColorChoice
    public var dark: ColorChoice

    public static let automatic = AppearanceColor(light: .automatic, dark: .automatic)

    public init(light: ColorChoice, dark: ColorChoice) {
        self.light = light
        self.dark = dark
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let choice = ColorChoice(rawValue: rawValue) else { return nil }
            self.init(light: choice, dark: choice)
        case 2:
            guard let light = ColorChoice(rawValue: String(parts[0])), let dark = ColorChoice(rawValue: String(parts[1])) else { return nil }
            self.init(light: light, dark: dark)
        default:
            return nil
        }
    }

    public var rawValue: String { "\(light.rawValue)|\(dark.rawValue)" }

    public func choice(isDark: Bool) -> ColorChoice { isDark ? dark : light }
}
