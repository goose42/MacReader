import Foundation
import Testing
@testable import MacReaderKit

struct EPUBPackageTests {
    private func package(_ spec: EPUBFixture.Spec) throws -> EPUBPackage {
        try EPUBPackage(container: EPUBContainer(data: EPUBFixture.archive(spec)))
    }

    private func chapters(_ count: Int) -> [EPUBFixture.Chapter] {
        (1...count).map { .init(file: "ch\($0).xhtml", navTitle: "Chapter \($0)", body: "<p>Text \($0).</p>") }
    }

    @Test func readsTheDublinCoreMetadataOfAnEPUB3() throws {
        var spec = EPUBFixture.Spec(chapters: chapters(1))
        spec.title = "Moby   Dick"
        spec.authors = ["Herman Melville"]
        spec.publisher = "Harper & Brothers"
        spec.date = "1851-10-18"
        spec.language = "en-US"
        spec.description = "<p>A <b>great</b> whale of a book.</p>"
        let package = try package(spec)

        #expect(package.title == "Moby Dick")
        #expect(package.authors == ["Herman Melville"])
        #expect(package.publisher == "Harper & Brothers")
        #expect(package.date == "1851-10-18")
        #expect(package.language == "en-US")
        #expect(package.summary == "A great whale of a book.")
        #expect(package.identifier == "urn:uuid:0001")
        #expect(package.path == "OEBPS/content.opf")
    }

    @Test func readsAnEPUB2WithOPFRoles() throws {
        var spec = EPUBFixture.Spec(chapters: chapters(1))
        spec.version = "2.0"
        spec.authors = ["Ann One", "Bo Two"]
        let package = try package(spec)
        #expect(package.title == "A Test Book")
        #expect(package.authors == ["Ann One", "Bo Two"])
        #expect(package.ncxPath == "OEBPS/toc.ncx")
        #expect(package.navigationPath == nil)
    }

    @Test func theMainTitleBeatsASubtitleListedFirst() throws {
        var spec = EPUBFixture.Spec(chapters: chapters(1))
        spec.editPackage = {
            $0.replacingOccurrences(
                of: "<dc:title id=\"t1\">A Test Book</dc:title>",
                with: "<dc:title id=\"t0\">The Subtitle</dc:title><meta refines=\"#t0\" property=\"title-type\">subtitle</meta><dc:title id=\"t1\">A Test Book</dc:title>")
        }
        #expect(try package(spec).title == "A Test Book")
    }

    @Test func authorsAreTheCreatorsWhoWroteIt() throws {
        var spec = EPUBFixture.Spec(chapters: chapters(1))
        spec.version = "2.0"
        spec.editPackage = {
            $0.replacingOccurrences(
                of: "</metadata>",
                with: "<dc:creator opf:role=\"ill\">Pat Pictures</dc:creator><dc:creator>Jane Author</dc:creator></metadata>")
        }
        #expect(try package(spec).authors == ["Jane Author"])
    }

    @Test func theSpineFollowsReadingOrderWithNonLinearItemsLast() throws {
        var spec = EPUBFixture.Spec(chapters: chapters(3))
        spec.chapters[0].linear = false
        let package = try package(spec)
        #expect(package.spine.map(\.path) == ["OEBPS/ch2.xhtml", "OEBPS/ch3.xhtml", "OEBPS/ch1.xhtml"])
        #expect(package.spine.allSatisfy { $0.mediaType == "application/xhtml+xml" })
    }

    @Test func findsTheNavigationDocumentAndPageDirection() throws {
        var spec = EPUBFixture.Spec(chapters: chapters(1))
        spec.rightToLeft = true
        let package = try package(spec)
        #expect(package.navigationPath == "OEBPS/nav.xhtml")
        #expect(package.pageProgression == "rtl")
    }

    @Test func hrefsAreResolvedAndUnescaped() throws {
        var spec = EPUBFixture.Spec(chapters: [.init(file: "text/My%20Chapter.xhtml", navTitle: nil, body: "<p>x</p>")])
        spec.extraFiles["OEBPS/text/My Chapter.xhtml"] = Data()
        #expect(try package(spec).spine.map(\.path) == ["OEBPS/text/My Chapter.xhtml"])
    }

    @Test func spineEntriesWithoutAManifestItemAreSkipped() throws {
        var spec = EPUBFixture.Spec(chapters: chapters(1))
        spec.editPackage = { $0.replacingOccurrences(of: "</spine>", with: "<itemref idref=\"ghost\"/></spine>") }
        #expect(try package(spec).spine.map(\.path) == ["OEBPS/ch1.xhtml"])
    }

    @Test func aDocumentThatIsNotAPackageIsRejected() throws {
        let zip = ZipFixture.make([
            .init(name: "META-INF/container.xml", data: Data("""
                <container><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
                """.utf8)),
            .init(name: "book.opf", data: Data("<html/>".utf8)),
        ])
        #expect(throws: EPUBContainer.Failure.notAnEPUB) { try EPUBPackage(container: EPUBContainer(data: zip)) }
    }
}
