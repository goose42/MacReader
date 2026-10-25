import Foundation
import Testing
@testable import MacReaderKit

struct ZipArchiveTests {
    private let text = Data(String(repeating: "Call me Ishmael. ", count: 50).utf8)

    @Test func readsStoredEntries() throws {
        let archive = try ZipArchive(data: ZipFixture.make([.init(name: "mimetype", data: Data("application/epub+zip".utf8))]))
        #expect(archive.names == ["mimetype"])
        #expect(try archive.data(for: "mimetype") == Data("application/epub+zip".utf8))
    }

    @Test func readsDeflatedEntries() throws {
        let archive = try ZipArchive(data: ZipFixture.make([.init(name: "OEBPS/ch1.xhtml", data: text, deflated: true)]))
        #expect(try archive.data(for: "OEBPS/ch1.xhtml") == text)
    }

    @Test func readsSeveralEntriesInAnyOrder() throws {
        let archive = try ZipArchive(data: ZipFixture.make([
            .init(name: "a.txt", data: Data("A".utf8)),
            .init(name: "b/c.txt", data: text, deflated: true),
            .init(name: "empty.txt", data: Data()),
        ]))
        #expect(archive.names == ["a.txt", "b/c.txt", "empty.txt"])
        #expect(try archive.data(for: "empty.txt").isEmpty)
        #expect(try archive.data(for: "b/c.txt") == text)
        #expect(try archive.data(for: "a.txt") == Data("A".utf8))
    }

    @Test func missingEntriesAreNil() throws {
        let archive = try ZipArchive(data: ZipFixture.make([.init(name: "a.txt", data: Data("A".utf8))]))
        #expect(archive.contains("a.txt"))
        #expect(!archive.contains("b.txt"))
        #expect(throws: ZipArchive.Failure.missingEntry("b.txt")) { try archive.data(for: "b.txt") }
    }

    @Test func findsEntriesWhosePathsArePercentEncoded() throws {
        let archive = try ZipArchive(data: ZipFixture.make([.init(name: "OEBPS/My Chapter.xhtml", data: Data("x".utf8))]))
        #expect(try archive.data(for: "OEBPS/My%20Chapter.xhtml") == Data("x".utf8))
    }

    @Test func rejectsABadChecksum() throws {
        var bytes = ZipFixture.make([.init(name: "a.txt", data: Data("hello".utf8))])
        // The stored text follows the 30-byte local header and the 5-byte name.
        bytes[35] ^= 0xFF
        let archive = try ZipArchive(data: bytes)
        #expect(throws: ZipArchive.Failure.corrupt("a.txt")) { try archive.data(for: "a.txt") }
    }

    @Test func rejectsEncryptedEntries() throws {
        let archive = try ZipArchive(data: ZipFixture.make([.init(name: "a.txt", data: Data("A".utf8), encrypted: true)]))
        #expect(throws: ZipArchive.Failure.encrypted("a.txt")) { try archive.data(for: "a.txt") }
    }

    @Test func rejectsDataThatIsNotAZip() {
        #expect(throws: ZipArchive.Failure.notAnArchive) { try ZipArchive(data: Data("%PDF-1.7".utf8)) }
        #expect(throws: ZipArchive.Failure.notAnArchive) { try ZipArchive(data: Data()) }
    }

    @Test func toleratesATrailingComment() throws {
        var bytes = ZipFixture.make([.init(name: "a.txt", data: Data("A".utf8))])
        // Replace the comment length (the last two bytes) and append a comment.
        bytes.removeLast(2)
        bytes.append(le16: 4)
        bytes.append(Data("note".utf8))
        let archive = try ZipArchive(data: bytes)
        #expect(try archive.data(for: "a.txt") == Data("A".utf8))
    }
}
