import Foundation
import Testing
@testable import MacReaderKit

/// Whole pages, with their junk, run through the full pipeline and scored against the article text by token F1.
///
/// Fixtures live in `Fixtures/HTML/<case>/` as `source.html` and `expected.txt`, plus `expected-metadata.json` for
/// the `mozilla-*` pages, which come from Mozilla Readability's test-pages (Apache-2.0, see MOZILLA-LICENSE.md). The
/// hand-written pages are held to a higher bar than real ones.
@MainActor
struct GoldenPageTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let minimumF1: Double
        var testDescription: String { name }
    }

    nonisolated private static let handWritten = 0.95
    nonisolated private static let real = 0.9

    nonisolated static let cases: [Case] = {
        let root = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/HTML")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { !$0.hasPrefix("MOZILLA") }.sorted().map { Case(name: $0, minimumF1: $0.hasPrefix("mozilla-") ? real : handWritten) }
    }()

    private func folder(_ golden: Case) throws -> URL {
        try #require(Bundle.module.url(forResource: golden.name, withExtension: nil, subdirectory: "Fixtures/HTML"))
    }

    @Test func thereAreRealPagesInTheCorpus() {
        #expect(Self.cases.filter { $0.name.hasPrefix("mozilla-") }.count >= 20)
    }

    @Test(arguments: cases) func extractsTheArticle(_ golden: Case) async throws {
        let folder = try folder(golden)
        let expected = try String(contentsOf: folder.appendingPathComponent("expected.txt"), encoding: .utf8)
        let result = try await HTMLTextExtractor.extract(pageAt: folder.appendingPathComponent("source.html"))
        let score = TokenScore(predicted: result.document.plainText, expected: expected)
        #expect(score.f1 >= golden.minimumF1, "\(golden.name): precision \(score.precision), recall \(score.recall)")
    }

    @Test(arguments: cases.filter { $0.name.hasPrefix("mozilla-") }) func findsTheTitle(_ golden: Case) async throws {
        let folder = try folder(golden)
        let data = try Data(contentsOf: folder.appendingPathComponent("expected-metadata.json"))
        let metadata = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected = (metadata["title"] as? String) ?? ""
        try #require(!expected.isEmpty)
        let result = try await HTMLTextExtractor.extract(pageAt: folder.appendingPathComponent("source.html"))
        #expect(TextSimilarity.score(expected, result.document.title) >= 0.75, "\(golden.name): “\(result.document.title)” vs “\(expected)”")
    }
}
