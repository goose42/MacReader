import Foundation
import Testing
@testable import MacReaderKit

struct HTMLSourceTests {
    @Test func decodesUTF8ByDefault() {
        #expect(HTMLSource.decode(Data("<p>café</p>".utf8)) == "<p>café</p>")
    }

    @Test func byteOrderMarkWinsOverMeta() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("<meta charset=\"iso-8859-1\"><p>café</p>".utf8))
        #expect(HTMLSource.decode(data).contains("café"))
    }

    @Test func decodesUTF16WithBOM() {
        let data = Data([0xFF, 0xFE]) + "<p>hi</p>".data(using: .utf16LittleEndian)!
        #expect(HTMLSource.decode(data) == "<p>hi</p>")
    }

    @Test func honoursMetaCharset() {
        let data = "<meta charset=\"windows-1252\"><p>café</p>".data(using: .windowsCP1252)!
        #expect(HTMLSource.decode(data).contains("café"))
    }

    @Test func honoursHTTPEquivContentType() {
        let html = "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=Shift_JIS\"><p>日本語</p>"
        let data = html.data(using: .shiftJIS)!
        #expect(HTMLSource.decode(data).contains("日本語"))
    }

    @Test func fallsBackToWindows1252WhenNotUTF8() {
        let data = "<p>café</p>".data(using: .windowsCP1252)!
        #expect(HTMLSource.decode(data).contains("café"))
    }

    @Test func findsTheFilesFolderBesideThePage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let files = folder.appendingPathComponent("My Page_files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let page = folder.appendingPathComponent("My Page.html")
        try Data().write(to: page)
        #expect(HTMLSource.resourcesFolder(for: page)?.standardizedFileURL == files.standardizedFileURL)
    }

    @Test func noFilesFolderMeansNil() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let page = folder.appendingPathComponent("lonely.html")
        try Data().write(to: page)
        #expect(HTMLSource.resourcesFolder(for: page) == nil)
    }

    @Test func readsTheChromeSavedFromComment() {
        let html = "<!DOCTYPE html>\n<!-- saved from url=(0035)https://example.com/a%2Db/post?x=1 -->\n<html></html>"
        #expect(HTMLSource.savedFromURL(in: html)?.absoluteString == "https://example.com/a-b/post?x=1")
    }

    @Test func noSavedFromCommentMeansNil() {
        #expect(HTMLSource.savedFromURL(in: "<html></html>") == nil)
    }

    @Test func collectsJSONLDBlocks() {
        let html = """
            <script>var x = 1;</script>
            <script type="application/ld+json">{"@type":"Article"}</script>
            <SCRIPT TYPE='application/ld+json' id=b>
              {"@type":"Person"}
            </SCRIPT>
            """
        #expect(HTMLSource.jsonLDBlocks(in: html) == [#"{"@type":"Article"}"#, #"{"@type":"Person"}"#])
    }
}
