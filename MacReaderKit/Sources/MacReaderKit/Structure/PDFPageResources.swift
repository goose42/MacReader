import CoreGraphics

/// Looks up entries of a page's resource dictionary, which a PDF may inherit from a parent node of the page tree.
enum PDFPageResources {
    static func dictionary(_ name: String, on page: CGPDFPage) -> CGPDFDictionaryRef? {
        var node = page.dictionary
        var resources: CGPDFDictionaryRef?
        while let current = node {
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources) { break }
            var parent: CGPDFDictionaryRef?
            node = CGPDFDictionaryGetDictionary(current, "Parent", &parent) ? parent : nil
        }
        var entry: CGPDFDictionaryRef?
        guard let resources, CGPDFDictionaryGetDictionary(resources, name, &entry) else { return nil }
        return entry
    }

    /// The dictionaries of each entry in a resource category such as `Font`, with their resource names.
    static func entries(_ category: String, on page: CGPDFPage) -> [(name: String, dictionary: CGPDFDictionaryRef)] {
        guard let dictionary = dictionary(category, on: page) else { return [] }
        final class Collector { var entries: [(name: String, dictionary: CGPDFDictionaryRef)] = [] }
        let collector = Collector()
        CGPDFDictionaryApplyBlock(dictionary, { key, object, info in
            var entry: CGPDFDictionaryRef?
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .dictionary, &entry), let entry {
                collector.entries.append((String(cString: key), entry))
            } else if CGPDFObjectGetValue(object, .stream, &stream), let stream, let entry = CGPDFStreamGetDictionary(stream) {
                collector.entries.append((String(cString: key), entry))
            }
            return true
        }, nil)
        return collector.entries
    }
}
