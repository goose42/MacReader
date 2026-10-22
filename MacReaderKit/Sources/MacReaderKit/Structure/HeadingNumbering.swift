import Foundation

/// Lifts section numbers out of headings: a short "MODULE 1" line above a heading becomes that heading's numbering,
/// and a leading "2.1" or "IV." is split off the heading text.
enum HeadingNumbering {
    nonisolated(unsafe) private static let eyebrow = /(?i)(module|chapter|section|part|unit|lesson|appendix)\s+([0-9]+|[ivxlc]+|[a-z])/
    nonisolated(unsafe) private static let bareNumber = /\d+(\.\d+)*\.?/
    nonisolated(unsafe) private static let inlinePrefix = /(\d{1,2}(?:\.\d+)+\.?|\d{1,2}\.?|[IVXLC]+\.|[A-Z]\.)\s+(\S.*)/

    static func apply(to blocks: [ReaderDocument.Block]) -> [ReaderDocument.Block] {
        var result: [ReaderDocument.Block] = []
        func append(_ block: ReaderDocument.Block, numbering: ReaderDocument.Numbering? = nil, text: String? = nil) {
            result.append(.init(id: result.count, kind: block.kind, text: text ?? block.text, numbering: numbering ?? block.numbering))
        }

        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if case .paragraph = block.kind, index + 1 < blocks.count,
               case .heading = blocks[index + 1].kind, blocks[index + 1].numbering == nil,
               let label = eyebrowLabel(block.text) {
                append(blocks[index + 1], numbering: .init(label: label, placement: .eyebrow))
                index += 2
                continue
            }
            if case .heading = block.kind, block.numbering == nil,
               let match = block.text.wholeMatch(of: inlinePrefix) {
                append(block, numbering: .init(label: String(match.1), placement: .inline), text: String(match.2))
            } else {
                append(block)
            }
            index += 1
        }
        return result
    }

    private static func eyebrowLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let match = trimmed.wholeMatch(of: eyebrow) {
            return "\(match.1.capitalized) \(match.2.uppercased())"
        }
        return trimmed.wholeMatch(of: bareNumber) != nil ? trimmed : nil
    }
}
