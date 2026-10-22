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

        let fingerprints = glyphs.mapValues { GlyphFingerprint(glyph: CGGlyph($0), in: font) }
        guard let spacer = glyphs.keys.filter({ $0 != spaceCode && fingerprints[$0] == .some(nil) }).min(),
              let spacerText = character(forCode: spacer) else { return [:] }

        var replacements: [String: String] = [:]
        for (code, fingerprint) in fingerprints {
            guard let fingerprint, let ligature = match(fingerprint), let codeText = character(forCode: code) else { continue }
            replacements[String(repeating: spacerText, count: ligature.count - 1) + codeText] = ligature
        }
        return replacements
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
