import Foundation
import Testing
import WebKit

@MainActor
struct WebKitSpikeTests {
    @Test func evaluatesJavaScriptAgainstALocalFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("page.html")
        try "<html><body><p id=a>Hello</p></body></html>".write(to: file, atomically: true, encoding: .utf8)

        let page = WebPage()
        let load = page.load(file)
        for try await _ in load {}
        let text = try await page.callJavaScript("return document.getElementById('a').textContent") as? String
        #expect(text == "Hello")
    }
}
