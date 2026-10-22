import Foundation
import PDFKit

public enum PDFTextExtractor {
    public enum Failure: Error, Equatable { case unreadable, noText }

    public struct Result: Equatable {
        public let document: ReaderDocument
        public let pageCount: Int
    }

    /// Reads a PDF into a structured document: ligatures repaired, the printed contents page dropped, and headings
    /// taken from the PDF's outline or inferred from font sizes.
    public static func extract(from data: Data, fallbackTitle: String = "Untitled") throws -> Result {
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { throw Failure.unreadable }

        var lines = PDFLineReader.lines(in: pdf)
        let repaired = LigatureRepairer(validator: SpellCheckerValidator()).repair(lines.map(\.text))
        lines = zip(lines, repaired).map { TextLine(text: $1, fontSize: $0.fontSize, pageIndex: $0.pageIndex) }
        lines = PrintedTOCDetector.strip(lines, bodySize: FontStatistics.bodySize(of: lines))

        var document = StructureBuilder.build(
            lines: lines, fallbackTitle: fallbackTitle, outline: PDFOutlineReader.entries(in: pdf))
        guard !document.blocks.isEmpty else { throw Failure.noText }

        if let title = metadataTitle(of: pdf) { document.title = title }
        return Result(document: document, pageCount: pdf.pageCount)
    }

    private static func metadataTitle(of pdf: PDFDocument) -> String? {
        let title = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }
}
