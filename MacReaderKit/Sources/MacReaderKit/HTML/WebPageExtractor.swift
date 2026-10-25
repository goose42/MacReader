import Foundation
import WebKit

/// Renders a saved page in a web view that can't run its scripts or reach the network, then runs the bundled
/// extraction scripts against the live document and returns what they report.
@MainActor
enum WebPageExtractor {
    enum Failure: Error, Equatable { case scriptsMissing, unreadable }

    /// Scripts in the order they must run; Readability's own two files come first, then ours.
    private static let scriptNames = ["Readability", "Readability-readerable", "junk-filter", "serialize"]

    private static let blockNetwork = """
        [{"trigger": {"url-filter": "^https?://.*"}, "action": {"type": "block"}}]
        """

    /// `cosmeticFilters` is the JSON of element-hiding rules to apply; by default the bundled filter lists.
    static func extract(html: String, baseURL: URL, cosmeticFilters: String? = nil) async throws -> ExtractionPayload {
        let script = try bundledScript(cosmeticFilters: cosmeticFilters ?? bundledFilters())

        let json = try await run(script, on: html, baseURL: baseURL)
        var payload = try JSONDecoder().decode(ExtractionPayload.self, from: Data(json.utf8))
        payload.metadata.jsonLD = HTMLSource.jsonLDBlocks(in: html)
        return payload
    }

    /// The body of `html` as a node tree, with no article-picking or junk filtering: markup that isn't well-formed
    /// XML, such as the text of a MOBI book, goes through here to be repaired by the browser's own parser.
    static func serializeBody(html: String, baseURL: URL) async throws -> XHTMLParser.Document {
        guard let serialize = resource("serialize", "js") else { throw Failure.scriptsMissing }
        let script = try String(contentsOf: serialize, encoding: .utf8) + "\nreturn mrBody();"

        let json = try await run(script, on: html, baseURL: baseURL)
        let report = try JSONDecoder().decode(BodyReport.self, from: Data(json.utf8))
        return XHTMLParser.Document(
            body: report.body, title: report.title, language: report.language, direction: report.direction)
    }

    /// Loads `html` in a web view that can't run its scripts or reach the network, runs `script` (a function body)
    /// against the live document, and returns the JSON string it reports.
    private static func run(_ script: String, on html: String, baseURL: URL) async throws -> String {
        var configuration = WebPage.Configuration()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = false
        if let rules = try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MacReaderBlockNetwork", encodedContentRuleList: blockNetwork) {
            configuration.userContentController.add(rules)
        }

        let page = WebPage(configuration: configuration)
        for try await _ in page.load(html: html, baseURL: baseURL) {}

        let world = WKContentWorld.world(name: "MacReaderExtraction")
        guard let json = try await page.callJavaScript(script, contentWorld: world) as? String else { throw Failure.unreadable }
        return json
    }

    private struct BodyReport: Decodable {
        var body: HTMLNode
        var title: String
        var language: String?
        var direction: String?
    }

    private static let noFilters = #"{"classes":[],"ids":[],"complex":{}}"#

    private static func resource(_ name: String, _ fileExtension: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources/HTML")
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "HTML")
    }

    private static func bundledFilters() -> String {
        resource("cosmetic-filters", "json").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? noFilters
    }

    /// The scripts joined into one function body ending in a call that returns the report as JSON, preceded by the
    /// element-hiding rules as a constant the junk filter reads.
    private static func bundledScript(cosmeticFilters: String) throws -> String {
        let sources = try scriptNames.map { name in
            guard let url = resource(name, "js") else { throw Failure.scriptsMissing }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return "const MR_COSMETIC = \(cosmeticFilters);\n" + sources.joined(separator: "\n") + "\nreturn mrExtract();"
    }
}
