import Foundation
import PDFKit

public enum PDFTextExtractor {
    public enum Failure: Error, Equatable { case unreadable, noText }

    public struct Result: Equatable {
        public let text: String
        public let title: String?
        public let pageCount: Int
    }

    public static func extract(from data: Data) throws -> Result {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw Failure.unreadable
        }
        let raw = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
        let text = TextNormalizer.normalize(raw)
        guard !text.isEmpty else { throw Failure.noText }

        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return Result(text: text, title: title, pageCount: document.pageCount)
    }
}
