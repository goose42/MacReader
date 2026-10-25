import Foundation
import Testing
@testable import MacReaderKit

struct EPUBPathTests {
    @Test func resolvesAgainstTheFolderOfTheReferringFile() {
        #expect(EPUBPath.resolve("ch1.xhtml", relativeTo: "OEBPS/content.opf") == "OEBPS/ch1.xhtml")
        #expect(EPUBPath.resolve("../images/a.png", relativeTo: "OEBPS/text/ch1.xhtml") == "OEBPS/images/a.png")
        #expect(EPUBPath.resolve("./a/./b.png", relativeTo: "x.opf") == "a/b.png")
    }

    @Test func dropsFragmentsAndQueriesAndDecodesEscapes() {
        #expect(EPUBPath.resolve("My%20File.xhtml#frag", relativeTo: "OEBPS/c.opf") == "OEBPS/My File.xhtml")
        #expect(EPUBPath.resolve("a.xhtml?x=1", relativeTo: "c.opf") == "a.xhtml")
        #expect(EPUBPath.resolve("#note", relativeTo: "OEBPS/ch1.xhtml") == "OEBPS/ch1.xhtml")
    }

    @Test func absolutePathsStartAtTheBookRoot() {
        #expect(EPUBPath.resolve("/images/a.png", relativeTo: "OEBPS/ch1.xhtml") == "images/a.png")
    }

    @Test func neverClimbsOutOfTheBook() {
        #expect(EPUBPath.resolve("../../../etc/passwd", relativeTo: "a/b.xhtml") == "etc/passwd")
    }

    @Test func addressesOutsideTheBookAreNotPaths() {
        #expect(EPUBPath.resolve("https://example.com/a.png", relativeTo: "c.opf") == nil)
        #expect(EPUBPath.resolve("data:image/png;base64,AAAA", relativeTo: "c.opf") == nil)
        #expect(EPUBPath.resolve("mailto:a@b.c", relativeTo: "c.opf") == nil)
        #expect(EPUBPath.resolve("", relativeTo: "c.opf") == nil)
    }

    @Test func readsTheFragment() {
        #expect(EPUBPath.fragment(of: "ch1.xhtml#note2") == "note2")
        #expect(EPUBPath.fragment(of: "ch1.xhtml") == nil)
    }
}

struct XMLTreeTests {
    private let container = Data("""
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
            <dc:title xmlns:dc="http://purl.org/dc/elements/1.1/" opf:role="aut" xml:lang="fr">  Le <b>Titre</b>&nbsp;ici </dc:title>
          </rootfiles>
        </container>
        """.utf8)

    @Test func namesAndAttributesLoseTheirPrefixes() throws {
        let root = try XMLTree.parse(container)
        #expect(root.name == "container")
        #expect(root.attributes == ["version": "1.0"])
        let title = try #require(root.descendants(named: "title").first)
        #expect(title.attributes == ["role": "aut", "lang": "fr"])
    }

    @Test func findsChildrenAndDescendants() throws {
        let root = try XMLTree.parse(container)
        #expect(root.child("rootfiles")?.children.map(\.name) == ["rootfile", "title"])
        #expect(root.descendants(named: "rootfile").first?.attributes["full-path"] == "OEBPS/content.opf")
        #expect(root.child("missing") == nil)
    }

    @Test func textContentJoinsNestedTextAndResolvesEntities() throws {
        let title = try #require(try XMLTree.parse(container).descendants(named: "title").first)
        #expect(title.textContent == "  Le Titre\u{A0}ici ")
        #expect(title.trimmedText == "Le Titre\u{A0}ici")
    }

    @Test func malformedXMLThrows() {
        #expect(throws: (any Error).self) { try XMLTree.parse(Data("<a><b></a>".utf8)) }
        #expect(throws: (any Error).self) { try XMLTree.parse(Data()) }
    }
}

struct EPUBContainerTests {
    private var spec: EPUBFixture.Spec {
        var spec = EPUBFixture.Spec()
        spec.chapters = [.init(file: "ch1.xhtml", navTitle: "One", body: "<p>Hello.</p>")]
        spec.extraFiles["OEBPS/images/a.png"] = Data([1, 2, 3])
        return spec
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try EPUBFixture.write(spec, to: url)
        return url
    }

    @Test func opensAZippedBook() throws {
        let container = try EPUBContainer(data: EPUBFixture.archive(spec))
        #expect(try container.packagePath() == "OEBPS/content.opf")
        #expect(container.contains("OEBPS/ch1.xhtml"))
        #expect(try container.data(at: "OEBPS/images/a.png") == Data([1, 2, 3]))
    }

    @Test func opensAnUnpackedBook() throws {
        let container = try EPUBContainer(contentsOf: try directory())
        #expect(try container.packagePath() == "OEBPS/content.opf")
        #expect(container.contains("OEBPS/ch1.xhtml"))
        #expect(!container.contains("OEBPS/missing.xhtml"))
        #expect(try container.data(at: "OEBPS/images/a.png") == Data([1, 2, 3]))
    }

    @Test func opensAZipFileByURL() throws {
        let container = try EPUBContainer(contentsOf: try EPUBFixture.writeArchive(spec))
        #expect(try container.packagePath() == "OEBPS/content.opf")
    }

    @Test func aMissingEntryIsReported() throws {
        let container = try EPUBContainer(data: EPUBFixture.archive(spec))
        #expect(throws: EPUBContainer.Failure.missing("nope.xhtml")) { try container.data(at: "nope.xhtml") }
    }

    @Test func aFolderCannotReadOutsideItself() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let book = parent.appendingPathComponent("book", isDirectory: true)
        try EPUBFixture.write(spec, to: book)
        try Data("secret".utf8).write(to: parent.appendingPathComponent("secret.txt"))
        let container = try EPUBContainer(contentsOf: book)
        #expect(!container.contains("../secret.txt"))
        #expect(throws: EPUBContainer.Failure.missing("../secret.txt")) { try container.data(at: "../secret.txt") }
    }

    @Test func aZipWithoutAPackageIsNotABook() throws {
        let zip = ZipFixture.make([.init(name: "hello.txt", data: Data("hi".utf8))])
        let container = try EPUBContainer(data: zip)
        #expect(throws: EPUBContainer.Failure.notAnEPUB) { try container.packagePath() }
    }

    @Test func somethingThatIsNotAZipIsNotABook() {
        #expect(throws: EPUBContainer.Failure.notAnEPUB) { try EPUBContainer(data: Data("%PDF-1.7".utf8)) }
    }

    @Test func aFolderWithoutContainerXMLIsNotABook() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let container = try EPUBContainer(contentsOf: empty)
        #expect(throws: EPUBContainer.Failure.notAnEPUB) { try container.packagePath() }
    }
}
