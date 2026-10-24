import Foundation
import Testing
@testable import MacReaderKit

/// Whole pages, with their junk, run through the full pipeline and scored against the article text by token F1.
@MainActor
struct GoldenPageTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let minimumF1: Double
        var testDescription: String { name }
    }

    nonisolated static let cases = [
        Case(name: "news-with-chrome", minimumF1: 0.95),
        Case(name: "blog-with-sidebar", minimumF1: 0.95),
        Case(name: "cjk-article", minimumF1: 0.95),
    ]

    @Test(arguments: cases) func extractsTheArticle(_ golden: Case) async throws {
        let folder = try #require(Bundle.module.url(forResource: golden.name, withExtension: nil, subdirectory: "Fixtures/HTML"))
        let expected = try String(contentsOf: folder.appendingPathComponent("expected.txt"), encoding: .utf8)
        let result = try await HTMLTextExtractor.extract(pageAt: folder.appendingPathComponent("source.html"))
        let score = TokenScore(predicted: result.document.plainText, expected: expected)
        #expect(score.f1 >= golden.minimumF1, "\(golden.name): precision \(score.precision), recall \(score.recall)")
    }
}
