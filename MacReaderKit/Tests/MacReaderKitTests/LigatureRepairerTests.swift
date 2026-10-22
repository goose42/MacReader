import Testing
@testable import MacReaderKit

struct LigatureRepairerTests {
    private struct StubValidator: WordValidator {
        let words: Set<String>
        func isValid(_ word: String) -> Bool { words.contains(word.lowercased()) }
    }

    private func repairer(_ words: String...) -> LigatureRepairer {
        LigatureRepairer(validator: StubValidator(words: Set(words)))
    }

    @Test func learnsDToFiFromSeveralWordsAndFixesThem() {
        let r = repairer("the", "is", "a", "file", "first", "specific")
        #expect(r.repair(["the Dle is Drst", "a speciDc Dle"]) == ["the file is first", "a specific file"])
    }

    @Test func leavesValidWordsAlone() {
        let r = repairer("file", "first", "dx", "the")
        #expect(r.repair(["the Dle", "Drst Dx"]) == ["the file", "first Dx"])
    }

    @Test func ignoresAllCapsAcronyms() {
        let r = repairer("file", "first")
        #expect(r.repair(["Dle Drst", "API DB KV"]) == ["file first", "API DB KV"])
    }

    @Test func doesNotLearnARuleFromASingleWordAlone() {
        let r = repairer("file")
        #expect(r.repair(["Dle"]) == ["Dle"])
    }

    @Test func acceptsASingleWordRuleOnceAnotherRuleWasLearned() {
        let r = repairer("file", "first", "payoff")
        #expect(r.repair(["Dle Drst", "payoR"]) == ["file first", "payoff"])
    }

    @Test func doesNotApplyARuleWhenTheReplacementIsNotAWord() {
        let r = repairer("file", "first", "finally", "specific")
        #expect(r.repair(["Dle Drst Dnally speciDc", "Dzzq"]) == ["file first finally specific", "Dzzq"])
    }

    @Test func repairsInteriorCapitalsEvenWhenTheValidatorIsLenientAboutCasing() {
        // NSSpellChecker accepts "payoR" because it ignores odd casing of a real word ("payor").
        let r = repairer("file", "first", "payoff", "payor", "mcdonald")
        #expect(r.repair(["Dle Drst", "payoR McDonald"]) == ["file first", "payoff McDonald"])
    }
}
