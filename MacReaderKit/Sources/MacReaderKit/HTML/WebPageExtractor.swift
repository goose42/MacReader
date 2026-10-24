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

    static func extract(html: String, baseURL: URL) async throws -> ExtractionPayload {
        let script = try bundledScript()

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
        var payload = try JSONDecoder().decode(ExtractionPayload.self, from: Data(json.utf8))
        payload.metadata.jsonLD = HTMLSource.jsonLDBlocks(in: html)
        return payload
    }

    /// The scripts joined into one function body ending in a call that returns the report as JSON.
    private static func bundledScript() throws -> String {
        let sources = try scriptNames.map { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Resources/HTML")
                ?? Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "HTML") else { throw Failure.scriptsMissing }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return sources.joined(separator: "\n") + "\nreturn mrExtract();"
    }
}
