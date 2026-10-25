import Foundation
import WebKit

/// Opens a web address in an offscreen browser, scripts and all, and returns the page as it looks once it has
/// rendered. Unlike `WebPageExtractor`, which reads a page with scripts off, this one lets the page run so that
/// articles drawn by script are there to be read.
@MainActor
public enum WebPageFetcher {
    public enum Failure: Error, Equatable {
        case loadFailed(String)
        case timedOut
    }

    public struct Snapshot: Sendable {
        /// The rendered document, headed by a `saved from url` comment naming `finalURL`.
        public let html: String
        /// Where the page ended up after redirects.
        public let finalURL: URL
    }

    /// `settle` is how long the page gets to finish drawing after it loads, and `timeout` bounds the whole fetch.
    public static func fetch(_ url: URL, settle: Duration = .seconds(1), timeout: Duration = .seconds(30)) async throws -> Snapshot {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration)

        var timedOut = false
        let work = Task { @MainActor in try await snapshot(of: page, loading: url, settle: settle) }
        let timer = Task { @MainActor in
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            timedOut = true
            work.cancel()
        }
        defer { timer.cancel() }

        do {
            return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        } catch {
            throw timedOut ? Failure.timedOut : error
        }
    }

    private static func snapshot(of page: WebPage, loading url: URL, settle: Duration) async throws -> Snapshot {
        do {
            for try await _ in page.load(URLRequest(url: url)) {}
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.loadFailed(error.localizedDescription)
        }
        // Lets the page finish drawing, then scrolls to the bottom once so pictures that load lazily start loading.
        try await Task.sleep(for: settle)
        _ = try? await page.callJavaScript("window.scrollTo(0, document.documentElement.scrollHeight)")
        try await Task.sleep(for: settle / 2)

        guard let markup = try await page.callJavaScript("return document.documentElement.outerHTML") as? String else {
            throw Failure.loadFailed("The page had no content.")
        }
        let finalURL = page.url ?? url
        let address = finalURL.absoluteString
        let header = "<!-- saved from url=(\(String(format: "%04d", address.utf8.count)))\(address) -->\n"
        return Snapshot(html: header + "<!DOCTYPE html>" + markup, finalURL: finalURL)
    }
}
