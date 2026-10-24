import AppKit
import Foundation
import Testing
@testable import MacReaderKit

@MainActor
struct HTMLTextExtractorTests {
    private static let filler = String(repeating: "The quick brown fox jumps over the lazy dog, again and again. ", count: 10)

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ html: String, named name: String = "Saved Page.html", in folder: URL, encoding: String.Encoding = .utf8) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try html.data(using: encoding)!.write(to: url)
        return url
    }

    private func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func expectFailure(_ expected: HTMLTextExtractor.Failure, extracting url: URL) async {
        do {
            _ = try await HTMLTextExtractor.extract(pageAt: url)
            Issue.record("expected \(expected)")
        } catch {
            #expect(error as? HTMLTextExtractor.Failure == expected)
        }
    }

    @Test func readsAnArticleIntoADocument() async throws {
        let url = try write("""
            <html><head><title>A Fine Post</title></head><body>
            <nav><a href="/">Home</a></nav>
            <article><h1>A Fine Post</h1><h2>First part</h2><p>\(Self.filler)</p><p>\(Self.filler)</p></article>
            </body></html>
            """, in: try folder())
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        #expect(result.document.title == "A Fine Post")
        #expect(result.document.blocks.first.map { $0.text } == "First part")
        #expect(result.document.blocks.contains { $0.text.contains("quick brown fox") })
        #expect(!result.document.plainText.contains("Home"))
    }

    @Test func decodesLegacyCharsets() async throws {
        let url = try write("""
            <html><head><meta charset="windows-1252"><title>Café</title></head><body>
            <article><p>\(Self.filler) Voilà, un café.</p><p>\(Self.filler)</p></article></body></html>
            """, in: try folder(), encoding: .windowsCP1252)
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        #expect(result.document.plainText.contains("un café"))
    }

    @Test func imagesFromTheFilesFolderComeAlong() async throws {
        let directory = try folder()
        let files = directory.appendingPathComponent("Saved Page_files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try png(width: 300, height: 150).write(to: files.appendingPathComponent("photo one.png"))
        let url = try write("""
            <html><head><title>Pictures</title></head><body><article>
            <p>\(Self.filler)</p>
            <figure><img src="Saved Page_files/photo one.png" alt="A photo"><figcaption>The photo.</figcaption></figure>
            <p>\(Self.filler)</p></article></body></html>
            """, in: directory)
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        let kinds = result.document.blocks.map(\.kind)
        guard let image = kinds.compactMap({ kind -> (String, Double)? in
            if case .image(let name, let ratio) = kind { return (name, ratio) }
            return nil
        }).first else { Issue.record("no image block"); return }
        #expect(image.1 == 2)
        #expect(result.images[image.0] != nil)
        #expect(result.document.blocks.contains { $0.kind == .caption && $0.text == "The photo." })
        #expect(result.resourcesFolder?.lastPathComponent == "Saved Page_files")
    }

    @Test func inlineDataImagesAreDecoded() async throws {
        let uri = "data:image/png;base64," + png(width: 100, height: 100).base64EncodedString()
        let url = try write("""
            <html><head><title>Inline</title></head><body><article><p>\(Self.filler)</p><img src="\(uri)"><p>\(Self.filler)</p></article></body></html>
            """, in: try folder())
        let result = try await HTMLTextExtractor.extract(pageAt: url)
        #expect(result.images.count == 1)
    }

    @Test func aPageWithoutAnArticleThrows() async throws {
        let url = try write("<html><body><div></div></body></html>", in: try folder())
        await expectFailure(.noArticle, extracting: url)
    }

    @Test func aMissingFileThrowsUnreadable() async throws {
        let url = try folder().appendingPathComponent("nope.html")
        await expectFailure(.unreadable, extracting: url)
    }
}
