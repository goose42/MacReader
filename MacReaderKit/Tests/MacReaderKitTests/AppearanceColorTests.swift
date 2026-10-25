import Testing
@testable import MacReaderKit

struct AppearanceColorTests {
    private let orange = ColorChoice.custom(red: 1, green: 128.0 / 255, blue: 0)

    @Test func automaticIsAutomaticInBothAppearances() {
        #expect(AppearanceColor.automatic.light == .automatic)
        #expect(AppearanceColor.automatic.dark == .automatic)
        #expect(AppearanceColor.automatic.rawValue == "automatic|automatic")
    }

    @Test func roundTripsThroughItsRawValue() {
        let color = AppearanceColor(light: orange, dark: .automatic)
        #expect(color.rawValue == "#FF8000|automatic")
        #expect(AppearanceColor(rawValue: "#FF8000|automatic") == color)
    }

    @Test func aLegacySingleColorAppliesToBothAppearances() {
        #expect(AppearanceColor(rawValue: "#FF8000") == AppearanceColor(light: orange, dark: orange))
        #expect(AppearanceColor(rawValue: "automatic") == .automatic)
    }

    @Test func choiceFollowsTheAppearance() {
        let color = AppearanceColor(light: orange, dark: .automatic)
        #expect(color.choice(isDark: false) == orange)
        #expect(color.choice(isDark: true) == .automatic)
    }

    @Test func malformedValuesAreRejected() {
        for bad in ["", "red", "#FF8000|red", "|", "#FF8000|automatic|automatic", "#FFF|#FFF"] {
            #expect(AppearanceColor(rawValue: bad) == nil, "\(bad)")
        }
    }
}
