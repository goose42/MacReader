import Foundation
import Testing
@testable import MacReaderKit

struct EPUBNavigationTests {
    private func navigation(_ spec: EPUBFixture.Spec) throws -> EPUBNavigation {
        let container = try EPUBContainer(data: EPUBFixture.archive(spec))
        return EPUBNavigation.load(from: container, package: try EPUBPackage(container: container))
    }

    private var chapters: [EPUBFixture.Chapter] {
        [
            .init(file: "ch1.xhtml", navTitle: "One", body: "<p>1</p>"),
            .init(file: "ch2.xhtml", navTitle: "Two", body: "<p>2</p>"),
        ]
    }

    @Test func readsTheNavigationDocumentOfAnEPUB3() throws {
        let navigation = try navigation(EPUBFixture.Spec(chapters: chapters))
        #expect(navigation.entries.map(\.title) == ["One", "Two"])
        #expect(navigation.entries.map(\.path) == ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])
        #expect(navigation.entries.map(\.depth) == [0, 0])
    }

    @Test func readsTheNCXOfAnEPUB2() throws {
        var spec = EPUBFixture.Spec(chapters: chapters)
        spec.version = "2.0"
        let navigation = try navigation(spec)
        #expect(navigation.entries.map(\.title) == ["One", "Two"])
        #expect(navigation.entries.map(\.path) == ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])
    }

    @Test func nestedListsGiveDepthAndFragments() throws {
        var spec = EPUBFixture.Spec(chapters: chapters)
        spec.navigationOverride = EPUBFixture.xhtml("""
            <nav epub:type="landmarks"><ol><li><a href="cover.xhtml">Cover</a></li></ol></nav>
            <nav epub:type="toc"><ol>
              <li><span>Part  I</span><ol>
                <li><a href="ch1.xhtml#start">  One
                  and more </a></li>
                <li><a href="ch2.xhtml">Two</a></li>
              </ol></li>
            </ol></nav>
            """)
        let entries = try navigation(spec).entries
        #expect(entries.map(\.title) == ["One and more", "Two"])
        #expect(entries.map(\.depth) == [1, 1])
        #expect(entries.first?.fragment == "start")
        #expect(entries.first?.path == "OEBPS/ch1.xhtml")
    }

    @Test func nestedNavPointsGiveDepth() throws {
        var spec = EPUBFixture.Spec(chapters: chapters)
        spec.version = "2.0"
        spec.navigationOverride = """
            <?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
            <navPoint id="a"><navLabel><text>Part</text></navLabel><content src="ch1.xhtml"/>
              <navPoint id="b"><navLabel><text>Sub</text></navLabel><content src="ch2.xhtml#s"/></navPoint>
            </navPoint></navMap></ncx>
            """
        let entries = try navigation(spec).entries
        #expect(entries.map(\.title) == ["Part", "Sub"])
        #expect(entries.map(\.depth) == [0, 1])
        #expect(entries.last?.fragment == "s")
    }

    @Test func anUnusableNavigationDocumentGivesNoEntries() throws {
        var spec = EPUBFixture.Spec(chapters: chapters)
        spec.navigationOverride = "<html><body><p>not xml"
        let container = try EPUBContainer(data: EPUBFixture.archive(spec))
        let package = try EPUBPackage(container: container)
        #expect(EPUBNavigation.load(from: container, package: package).entries.isEmpty)
    }

    @Test func aBookWithoutNavigationHasNoEntries() throws {
        var spec = EPUBFixture.Spec(chapters: [.init(file: "ch1.xhtml", navTitle: nil, body: "<p>x</p>")])
        spec.navigationOverride = EPUBFixture.xhtml("<p>no nav</p>")
        #expect(try navigation(spec).entries.isEmpty)
    }

    @Test func aChapterTakesTheTitleOfItsFirstEntry() throws {
        var spec = EPUBFixture.Spec(chapters: chapters)
        spec.navigationOverride = EPUBFixture.xhtml("""
            <nav epub:type="toc"><ol><li><a href="ch1.xhtml">Opening</a></li><li><a href="ch1.xhtml#later">Later</a></li></ol></nav>
            """)
        let navigation = try navigation(spec)
        #expect(navigation.title(forChapterAt: "OEBPS/ch1.xhtml") == "Opening")
        #expect(navigation.title(forChapterAt: "OEBPS/ch2.xhtml") == nil)
    }
}

struct EPUBProtectionTests {
    private func isProtected(_ spec: EPUBFixture.Spec) throws -> Bool {
        EPUBProtection.isProtected(try EPUBContainer(data: EPUBFixture.archive(spec)))
    }

    private func encryption(_ algorithm: String, uri: String = "OEBPS/fonts/a.otf") -> String {
        """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:EncryptionMethod Algorithm="\(algorithm)"/>
        <enc:CipherData><enc:CipherReference URI="\(uri)"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """
    }

    @Test func anOrdinaryBookIsNotProtected() throws {
        #expect(try !isProtected(EPUBFixture.Spec()))
    }

    @Test func fontObfuscationIsNotProtection() throws {
        var spec = EPUBFixture.Spec()
        spec.encryptionXML = encryption("http://www.idpf.org/2008/embedding")
        #expect(try !isProtected(spec))
        spec.encryptionXML = encryption("http://ns.adobe.com/pdf/enc#RC")
        #expect(try !isProtected(spec))
    }

    @Test func encryptedContentIsProtection() throws {
        var spec = EPUBFixture.Spec()
        spec.encryptionXML = encryption("http://www.w3.org/2001/04/xmlenc#aes128-cbc", uri: "OEBPS/ch1.xhtml")
        #expect(try isProtected(spec))
    }

    @Test func rightsAndFairPlayFilesAreProtection() throws {
        var spec = EPUBFixture.Spec()
        spec.extraFiles["META-INF/rights.xml"] = Data("<rights/>".utf8)
        #expect(try isProtected(spec))
        spec.extraFiles = ["META-INF/sinf.xml": Data("<sinf/>".utf8)]
        #expect(try isProtected(spec))
    }

    @Test func anUnreadableEncryptionFileIsTreatedAsProtection() throws {
        var spec = EPUBFixture.Spec()
        spec.encryptionXML = "<encryption><broken"
        #expect(try isProtected(spec))
    }
}
