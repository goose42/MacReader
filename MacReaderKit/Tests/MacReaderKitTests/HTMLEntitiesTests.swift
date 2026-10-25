import Testing
@testable import MacReaderKit

struct HTMLEntitiesTests {
    @Test func decodesNumericEntities() {
        #expect(HTMLEntities.decode("Yemen&#039;s and &#x27;quoted&#X27; &#8217;") == "Yemen's and 'quoted' ’")
    }

    @Test func decodesCommonNamedEntities() {
        #expect(HTMLEntities.decode("a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos; f&nbsp;g &mdash; &ndash; &hellip; &rsquo; &ldquo;&rdquo;") == "a & b <c> \"d\" 'e' f\u{A0}g — – … ’ “”")
    }

    @Test func leavesUnknownAndMalformedEntitiesAlone() {
        #expect(HTMLEntities.decode("&bogus; &#; & &amp") == "&bogus; &#; & &amp")
    }

    @Test func doesNotDecodeTwice() {
        #expect(HTMLEntities.decode("&amp;lt;") == "&lt;")
    }
}
