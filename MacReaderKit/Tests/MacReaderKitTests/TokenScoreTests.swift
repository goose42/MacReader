import Testing

struct TokenScoreTests {
    @Test func identicalTextScoresOne() {
        #expect(TokenScore(predicted: "The quick brown fox", expected: "the quick   brown FOX").f1 == 1)
    }

    @Test func disjointTextScoresZero() {
        #expect(TokenScore(predicted: "alpha beta", expected: "gamma delta").f1 == 0)
    }

    @Test func twoEmptyTextsScoreOne() {
        #expect(TokenScore(predicted: "", expected: " ").f1 == 1)
        #expect(TokenScore(predicted: "word", expected: "").f1 == 0)
    }

    @Test func extraTextLowersPrecisionAndMissingTextLowersRecall() {
        let extra = TokenScore(predicted: "a b c d", expected: "a b")
        #expect(extra.precision == 0.5 && extra.recall == 1)
        let missing = TokenScore(predicted: "a b", expected: "a b c d")
        #expect(missing.precision == 1 && missing.recall == 0.5)
    }

    @Test func repeatedWordsCountAsManyTimesAsTheyAppear() {
        #expect(TokenScore(predicted: "a a a", expected: "a").precision == 1.0 / 3)
    }

    @Test func cjkTextIsScoredPerCharacter() {
        #expect(TokenScore(predicted: "今日は晴れ", expected: "今日は雨").recall == 0.75)
    }
}
