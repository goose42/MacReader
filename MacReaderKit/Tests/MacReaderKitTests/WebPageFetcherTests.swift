import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct WebPageFetcherTests {
    private func write(_ html: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("page.html")
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let renderedLater = """
        <!DOCTYPE html><html><head><title>Late</title></head><body><div id="root"></div>
        <script>setTimeout(() => { document.getElementById('root').innerHTML = '<article><p>Rendered by script.</p></article>' }, 100)</script>
        </body></html>
        """

    @Test func snapshotsThePageAfterItsScriptsHaveRun() async throws {
        let url = try write(renderedLater)
        let snapshot = try await WebPageFetcher.fetch(url, settle: .milliseconds(600))
        #expect(snapshot.html.contains("Rendered by script."))
    }

    @Test func recordsWhereThePageCameFromSoItsSourceIsKnown() async throws {
        let url = try write(renderedLater)
        let snapshot = try await WebPageFetcher.fetch(url, settle: .milliseconds(100))
        #expect(snapshot.finalURL.lastPathComponent == "page.html")
        #expect(HTMLSource.savedFromURL(in: snapshot.html)?.lastPathComponent == "page.html")
    }

    @Test func givesUpWhenThePageTakesTooLong() async throws {
        let url = try write(renderedLater)
        do {
            _ = try await WebPageFetcher.fetch(url, settle: .seconds(5), timeout: .milliseconds(200))
            Issue.record("expected a timeout")
        } catch {
            #expect(error as? WebPageFetcher.Failure == .timedOut)
        }
    }

    @Test func aPageThatCannotBeLoadedFails() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/nope.html")
        do {
            _ = try await WebPageFetcher.fetch(missing, settle: .milliseconds(10))
            Issue.record("expected a failure")
        } catch let failure as WebPageFetcher.Failure {
            guard case .loadFailed = failure else { Issue.record("wrong failure \(failure)"); return }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
