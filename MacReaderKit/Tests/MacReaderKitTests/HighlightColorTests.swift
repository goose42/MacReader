import Testing
@testable import MacReaderKit

struct HighlightColorTests {
    @Test func accentRoundTripsThroughItsRawValue() {
        #expect(HighlightColor.accent.rawValue == "accent")
        #expect(HighlightColor(rawValue: "accent") == .accent)
    }

    @Test func customColorsAreStoredAsHex() {
        let color = HighlightColor.custom(red: 1, green: 0.5, blue: 0)
        #expect(color.rawValue == "#FF8000")
        #expect(HighlightColor(rawValue: "#FF8000") == .custom(red: 1, green: 128.0 / 255, blue: 0))
    }

    @Test func hexParsingIsCaseInsensitive() {
        #expect(HighlightColor(rawValue: "#ff8000") == HighlightColor(rawValue: "#FF8000"))
    }

    @Test func componentsAreClampedWhenEncoding() {
        #expect(HighlightColor.custom(red: 2, green: -1, blue: 0).rawValue == "#FF0000")
    }

    @Test func malformedValuesAreRejected() {
        for bad in ["", "red", "#FFF", "#GG0000", "FF8000", "#FF800000", "#+FF800"] {
            #expect(HighlightColor(rawValue: bad) == nil, "\(bad)")
        }
    }
}
