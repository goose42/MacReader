import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Recovers the text of code ligatures that PDFKit extracts as punctuation.
///
/// JetBrains Mono (and fonts built like it) draws `-->` as two empty spacer glyphs followed by one wide ligature glyph.
/// PDF generators embed it as a subset with no Unicode map, so PDFKit reports the spacers as `!` and the ligature as
/// whatever code it was given: `L1 !!% L2`. Each glyph is named here by comparing its outline with the real font's.
enum CodeLigatureDecoder {
    private static let minimumSimilarity = 0.8
    private static let minimumMargin = 0.05
    private static let spaceCode = 0x20

    nonisolated(unsafe) private static let table: [(text: String, fingerprint: GlyphFingerprint)] =
        CodeLigatureTable.entries.compactMap { entry in
            GlyphFingerprint(hex: entry.fingerprint).map { (entry.text, $0) }
        }

    /// The garbled text each ligature in an embedded font comes out as, mapped to what it really says.
    static func replacements(forFont data: Data) -> [String: String] {
        let glyphs = TrueTypeCMap.glyphs(in: data)
        guard !glyphs.isEmpty, let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider) else { return [:] }
        let font = CTFontCreateWithGraphicsFont(cgFont, 100, nil, nil)

        // Only fonts with an empty glyph besides the space are built this way, which is cheap to check.
        guard let spacer = glyphs.keys.filter({ code in
            code != spaceCode && (CTFontCreatePathForGlyph(font, CGGlyph(glyphs[code]!), nil)?.isEmpty ?? true)
        }).min(), let spacerText = character(forCode: spacer) else { return [:] }


        var replacements: [String: String] = [:]
        for (code, glyph) in glyphs where code != spacer {
            // A ligature is the last glyph of its run, so its outline reaches back left over the cells before it.
            guard let path = CTFontCreatePathForGlyph(font, CGGlyph(glyph), nil), path.boundingBox.minX < 0,
                  let fingerprint = GlyphFingerprint(glyph: CGGlyph(glyph), in: font),
                  let ligature = match(fingerprint), let codeText = character(forCode: code) else { continue }
            replacements[String(repeating: spacerText, count: ligature.count - 1) + codeText] = ligature
        }
        return replacements
    }

    /// Remembers what each embedded font decodes to, since a document repeats the same few fonts on every page.
    final class Cache {
        fileprivate var fonts: [Data: [String: String]] = [:]
    }

    /// The replacements for every embedded font on `page`. A run that two fonts read differently is dropped rather
    /// than guessed.
    ///
    /// The font's own Unicode map is no guide: Chrome writes an identity map for these fonts, which is how the
    /// ligature came to be extracted as punctuation in the first place.
    static func replacements(on page: PDFPage, cache: Cache = Cache()) -> [String: String] {
        guard let pageRef = page.pageRef else { return [:] }
        var merged: [String: String] = [:]
        var conflicting: Set<String> = []
        for (_, font) in PDFPageResources.entries("Font", on: pageRef) {
            guard let data = embeddedTrueType(font) else { continue }
            let fontReplacements = cache.fonts[data] ?? replacements(forFont: data)
            cache.fonts[data] = fontReplacements
            for (run, text) in fontReplacements {
                if let existing = merged[run], existing != text { conflicting.insert(run) }
                merged[run] = text
            }
        }
        conflicting.forEach { merged[$0] = nil }
        return merged
    }

    /// The font file of a simple TrueType font, if the PDF embeds one.
    private static func embeddedTrueType(_ font: CGPDFDictionaryRef) -> Data? {
        var descriptor: CGPDFDictionaryRef?
        var file: CGPDFStreamRef?
        guard CGPDFDictionaryGetDictionary(font, "FontDescriptor", &descriptor), let descriptor,
              CGPDFDictionaryGetStream(descriptor, "FontFile2", &file), let file else { return nil }
        var format = CGPDFDataFormat.raw
        return CGPDFStreamCopyData(file, &format) as Data?
    }

    /// Replaces every garbled run in `line`, preferring the longest run at each position.
    static func apply(_ replacements: [String: String], to line: String) -> String {
        guard !replacements.isEmpty else { return line }
        let runs = replacements.keys.sorted { $0.count > $1.count }
        var result = ""
        var rest = Substring(line)
        while let first = rest.first {
            if let run = runs.first(where: { rest.hasPrefix($0) }) {
                result += replacements[run]!
                rest = rest.dropFirst(run.count)
            } else {
                result.append(first)
                rest = rest.dropFirst()
            }
        }
        return result
    }

    // MARK: - Matching

    /// The ligature whose outline is clearly the closest to `fingerprint`, if any is close enough to trust.
    private static func match(_ fingerprint: GlyphFingerprint) -> String? {
        var scores: [String: Double] = [:]
        for entry in table {
            scores[entry.text] = max(scores[entry.text] ?? 0, fingerprint.similarity(to: entry.fingerprint))
        }
        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value >= minimumSimilarity,
              best.value - (ranked.dropFirst().first?.value ?? 0) >= minimumMargin else { return nil }
        return best.key
    }

    private static func character(forCode code: Int) -> String? {
        guard (0..<256).contains(code) else { return nil }
        return String(bytes: [UInt8(code)], encoding: .macOSRoman)
    }
}
