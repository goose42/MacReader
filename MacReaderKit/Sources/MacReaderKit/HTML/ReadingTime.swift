import Foundation

/// How long an article takes to read, from characters per minute by language (Firefox Reader View's table).
enum ReadingTime {
    private static let charactersPerMinute: [String: Double] = ["en": 987, "de": 920, "ja": 357, "zh": 255]

    static func minutes(characters: Int, language: String?) -> Int {
        let subtag = language?.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        let rate = subtag.flatMap { charactersPerMinute[$0] } ?? charactersPerMinute["en"]!
        return max(1, Int((Double(characters) / rate).rounded(.up)))
    }
}

extension ReaderDocument {
    /// Minutes to read the text, not counting code, tables, footnotes or pictures; nil for a document with none.
    public var estimatedReadingMinutes: Int? {
        let characters = blocks.reduce(0) { total, block in
            switch block.kind {
            case .paragraph, .heading, .listItem, .quote, .callout: total + block.text.count
            default: total
            }
        }
        return characters == 0 ? nil : ReadingTime.minutes(characters: characters, language: metadata?.language)
    }
}
