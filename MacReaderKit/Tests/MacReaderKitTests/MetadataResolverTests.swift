import Foundation
import Testing
@testable import MacReaderKit

struct MetadataResolverTests {
    private func raw(
        title: String = "", meta: [String: String] = [:], jsonLD: [String] = [], headings: [String] = [],
        language: String? = nil, direction: String? = nil, canonical: String? = nil, base: String? = nil
    ) -> RawMetadata {
        var raw = RawMetadata()
        raw.title = title
        raw.meta = meta.sorted { $0.key < $1.key }.map { .init(key: $0.key, content: $0.value) }
        raw.jsonLD = jsonLD
        raw.headings = headings
        raw.language = language
        raw.direction = direction
        raw.canonicalURL = canonical
        raw.baseURL = base
        return raw
    }

    private func readability(title: String? = nil, byline: String? = nil, excerpt: String? = nil, siteName: String? = nil, published: String? = nil) -> ReadabilityResult {
        ReadabilityResult(content: HTMLNode(tag: "div"), title: title, byline: byline, excerpt: excerpt, siteName: siteName, publishedTime: published)
    }

    private func resolve(_ raw: RawMetadata, _ readability: ReadabilityResult? = nil, saved: URL? = nil) -> MetadataResolver.Resolved {
        MetadataResolver.resolve(raw, readability: readability, savedFromURL: saved, now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    // MARK: - Title

    @Test func jsonLDHeadlineWinsOverOpenGraphAndTitle() {
        let ld = #"{"@context":"https://schema.org","@type":"NewsArticle","headline":"LD Headline"}"#
        #expect(resolve(raw(title: "Doc Title", meta: ["og:title": "OG Title"], jsonLD: [ld])).title == "LD Headline")
    }

    @Test func openGraphTitleBeatsTheDocumentTitle() {
        #expect(resolve(raw(title: "Doc Title", meta: ["og:title": "OG Title"])).title == "OG Title")
    }

    @Test func fallsBackToReadabilityThenTheHeading() {
        #expect(resolve(raw(), readability(title: "From Readability")).title == "From Readability")
        #expect(resolve(raw(headings: ["Only Heading"])).title == "Only Heading")
        #expect(resolve(raw()).title == nil)
    }

    @Test func aSiteNameSuffixIsStrippedFromTheTitle() {
        let resolved = resolve(raw(title: "How Bridges Work | Example Times", meta: ["og:site_name": "Example Times"]))
        #expect(resolved.title == "How Bridges Work")
    }

    @Test func aPrefixSiteNameIsStrippedToo() {
        let resolved = resolve(raw(title: "Example Times – How Bridges Work", meta: ["og:site_name": "Example Times"]))
        #expect(resolved.title == "How Bridges Work")
    }

    @Test func theHostCanIdentifyTheSiteWhenThereIsNoSiteName() {
        let resolved = resolve(raw(title: "How Bridges Work - Example", canonical: "https://www.example.com/a"))
        #expect(resolved.title == "How Bridges Work")
    }

    @Test func aTitleWithUnrelatedDashesIsLeftAlone() {
        #expect(resolve(raw(title: "Pros - Cons of Dashes")).title == "Pros - Cons of Dashes")
    }

    @Test func aHeadingPicksTheArticleHalfOfASplitTitle() {
        let resolved = resolve(raw(title: "Latest: How Bridges Work | Daily", headings: ["How Bridges Work"]))
        #expect(resolved.title == "How Bridges Work")
    }

    // MARK: - Byline

    @Test func jsonLDAuthorsAreJoined() {
        let ld = #"{"@type":"Article","author":[{"@type":"Person","name":"Ada"},{"@type":"Person","name":"Grace"}]}"#
        #expect(resolve(raw(jsonLD: [ld])).byline == "Ada, Grace")
    }

    @Test func graphAuthorReferencesAreResolved() {
        let ld = ##"{"@graph":[{"@type":"Article","author":{"@id":"#a"}},{"@type":"Person","@id":"#a","name":"Ada Lovelace"}]}"##
        #expect(resolve(raw(jsonLD: [ld])).byline == "Ada Lovelace")
    }

    @Test func aStringAuthorWorks() {
        #expect(resolve(raw(jsonLD: [#"{"@type":"BlogPosting","author":"Ada"}"#])).byline == "Ada")
    }

    @Test func metaAuthorFollowsAndUrlsAreRejected() {
        #expect(resolve(raw(meta: ["author": "Meta Author"])).byline == "Meta Author")
        #expect(resolve(raw(meta: ["article:author": "https://facebook.com/ada"]), readability(byline: "By Body Byline")).byline == "Body Byline")
    }

    @Test func bylinePrefixesAndLengthAreCleaned() {
        #expect(resolve(raw(), readability(byline: "  By  Ada Lovelace  ")).byline == "Ada Lovelace")
        #expect(resolve(raw(), readability(byline: String(repeating: "x", count: 150))).byline == nil)
    }

    // MARK: - Date

    @Test func jsonLDPublishedDateIsParsed() {
        let ld = #"{"@type":"Article","datePublished":"2024-05-01T10:30:00Z"}"#
        #expect(resolve(raw(jsonLD: [ld])).publishedDate == ISO8601DateFormatter().date(from: "2024-05-01T10:30:00Z"))
    }

    @Test func metaDatesAcceptDateOnlyAndFractionalSeconds() {
        #expect(resolve(raw(meta: ["article:published_time": "2024-05-01"])).publishedDate != nil)
        #expect(resolve(raw(meta: ["article:published_time": "2024-05-01T10:30:00.123Z"])).publishedDate != nil)
    }

    @Test func futureAndGarbageDatesAreRejected() {
        #expect(resolve(raw(meta: ["article:published_time": "2099-01-01"])).publishedDate == nil)
        #expect(resolve(raw(meta: ["article:published_time": "someday"])).publishedDate == nil)
    }

    // MARK: - Site, language, excerpt, URL

    @Test func siteNameComesFromOpenGraphThenJSONLDPublisher() {
        #expect(resolve(raw(meta: ["og:site_name": "OG Site"])).siteName == "OG Site")
        #expect(resolve(raw(jsonLD: [#"{"@type":"Article","publisher":{"@type":"Organization","name":"LD Pub"}}"#])).siteName == "LD Pub")
    }

    @Test func languageAndDirection() {
        #expect(resolve(raw(language: "en-GB")).language == "en-GB")
        #expect(resolve(raw(meta: ["og:locale": "fr_FR"])).language == "fr-FR")
        #expect(resolve(raw(language: "ar")).isRightToLeft)
        #expect(resolve(raw(language: "en", direction: "rtl")).isRightToLeft)
        #expect(!resolve(raw(language: "en")).isRightToLeft)
    }

    @Test func excerptPrefersDescriptions() {
        #expect(resolve(raw(meta: ["description": "Meta desc", "og:description": "OG desc"])).excerpt == "OG desc")
        #expect(resolve(raw(), readability(excerpt: "Body excerpt")).excerpt == "Body excerpt")
    }

    @Test func sourceURLPrefersCanonicalThenOpenGraphThenSavedFrom() {
        #expect(resolve(raw(meta: ["og:url": "https://og.example/a"], canonical: "https://canon.example/a")).sourceURL?.host == "canon.example")
        #expect(resolve(raw(meta: ["og:url": "https://og.example/a"])).sourceURL?.host == "og.example")
        #expect(resolve(raw(), saved: URL(string: "https://saved.example/a")).sourceURL?.host == "saved.example")
        #expect(resolve(raw(canonical: "/relative/only")).sourceURL == nil)
    }

    // MARK: - Reading time

    @Test func readingTimeRoundsUpAndNeverShowsZero() {
        #expect(ReadingTime.minutes(characters: 10, language: "en") == 1)
        #expect(ReadingTime.minutes(characters: 987 * 5, language: "en") == 5)
        #expect(ReadingTime.minutes(characters: 987 * 5 + 1, language: "en-US") == 6)
    }

    @Test func slowerScriptsTakeLonger() {
        #expect(ReadingTime.minutes(characters: 3000, language: "ja") > ReadingTime.minutes(characters: 3000, language: "en"))
        #expect(ReadingTime.minutes(characters: 3000, language: "zh-CN") > ReadingTime.minutes(characters: 3000, language: "de"))
    }

    @Test func aDocumentCountsOnlyItsReadableText() {
        let text = String(repeating: "a", count: 1974)
        let document = ReaderDocument(title: "T", blocks: [
            .init(id: 0, kind: .paragraph, text: text),
            .init(id: 1, kind: .code, text: String(repeating: "x", count: 5000)),
            .init(id: 2, kind: .image(name: "a.png", aspectRatio: 1), text: ""),
        ])
        #expect(document.estimatedReadingMinutes == 2)
    }
}
