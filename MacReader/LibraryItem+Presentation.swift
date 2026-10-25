import MacReaderKit
import UniformTypeIdentifiers

extension UTType {
    /// Kindle books (MOBI, AZW, AZW3, PRC), declared as an imported type in the app's Info.plist because the system
    /// has no type of its own for them.
    static let kindleBook = UTType(importedAs: "com.amazon.mobi-ebook", conformingTo: .data)

    /// What the Add File… panel offers. Folders are allowed so a saved page's "…_files" folder can be chosen along
    /// with it, and so an unpacked EPUB can be.
    static let libraryDocuments: [UTType] = [.pdf, .html, .epub, .kindleBook, .folder]
}

extension MacReaderKit.LibraryItem {
    /// The SF Symbol shown beside the item in the library.
    var symbolName: String {
        switch sourceKind {
        case .pdf: "doc.text"
        case .html: "globe"
        case .epub, .mobi: "book.closed"
        }
    }

    /// The line under the title: who wrote or published it, then when it was added.
    var subtitle: String {
        let date = dateAdded.formatted(.dateTime.month().day().year())
        return (author ?? siteName).map { "\($0) · \(date)" } ?? date
    }
}
