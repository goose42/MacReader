import Foundation
import Testing
@testable import MacReaderKit

struct WebAddressTests {
    @Test func keepsAnHTTPSAddress() {
        #expect(WebAddress.parse("https://example.com/a?b=1")?.absoluteString == "https://example.com/a?b=1")
    }

    @Test func keepsAnHTTPAddress() {
        #expect(WebAddress.parse("http://example.com")?.scheme == "http")
    }

    @Test func trimsWhitespaceAndNewlines() {
        #expect(WebAddress.parse("  https://example.com/post \n")?.absoluteString == "https://example.com/post")
    }

    @Test func addsHTTPSWhenTheSchemeIsMissing() {
        #expect(WebAddress.parse("example.com/post")?.absoluteString == "https://example.com/post")
    }

    @Test func rejectsOtherSchemes() {
        #expect(WebAddress.parse("ftp://example.com/file") == nil)
        #expect(WebAddress.parse("file:///etc/hosts") == nil)
        #expect(WebAddress.parse("javascript:alert(1)") == nil)
    }

    @Test func rejectsTextThatIsNotAnAddress() {
        #expect(WebAddress.parse("") == nil)
        #expect(WebAddress.parse("   ") == nil)
        #expect(WebAddress.parse("notaurl") == nil)
        #expect(WebAddress.parse("two words.com") == nil)
    }

    @Test func namesAnItemAfterItsHostAndPath() {
        let url = URL(string: "https://www.example.com/2026/post?id=3")!
        #expect(WebAddress.fileName(for: url) == "www.example.com/2026/post")
        #expect(WebAddress.fileName(for: URL(string: "https://example.com/")!) == "example.com")
    }
}
