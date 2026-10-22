import Testing
@testable import MacReaderKit

struct SpellCheckerValidatorTests {
    @Test func recognisesRealWordsAndRejectsNonWords() {
        let validator = SpellCheckerValidator()
        #expect(validator.isValid("file"))
        #expect(validator.isValid("File"))
        #expect(!validator.isValid("Dle"))
        #expect(!validator.isValid("speciDc"))
    }
}
