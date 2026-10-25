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

    @Test func decodesTheLatin1AndTypographicEntitiesXHTMLUses() {
        #expect(HTMLEntities.decode("caf&eacute; &Aacute;&uuml;&yuml; 6&divide;3 &frac12; &euro; &thinsp;&ensp;&emsp;") == "café Áüÿ 6÷3 ½ € \u{2009}\u{2002}\u{2003}")
        #expect(HTMLEntities.decode("&iexcl;&uml;&shy;&copy;&reg;&sup2;&times;&szlig;&thorn;") == "¡¨\u{AD}©®²×ßþ")
    }
}
