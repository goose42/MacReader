import Testing
@testable import MacReaderKit

struct ColorChoiceTests {
    @Test func automaticRoundTripsThroughItsRawValue() {
        #expect(ColorChoice.automatic.rawValue == "automatic")
        #expect(ColorChoice(rawValue: "automatic") == .automatic)
    }

    @Test func customColorsAreStoredAsHex() {
        let color = ColorChoice.custom(red: 1, green: 0.5, blue: 0)
        #expect(color.rawValue == "#FF8000")
        #expect(ColorChoice(rawValue: "#FF8000") == .custom(red: 1, green: 128.0 / 255, blue: 0))
    }

    @Test func hexParsingIsCaseInsensitive() {
        #expect(ColorChoice(rawValue: "#ff8000") == ColorChoice(rawValue: "#FF8000"))
    }

    @Test func componentsAreClampedWhenEncoding() {
        #expect(ColorChoice.custom(red: 2, green: -1, blue: 0).rawValue == "#FF0000")
    }

    @Test func malformedValuesAreRejected() {
        for bad in ["", "red", "#FFF", "#GG0000", "FF8000", "#FF800000", "#+FF800"] {
            #expect(ColorChoice(rawValue: bad) == nil, "\(bad)")
        }
    }
}
