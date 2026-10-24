import Foundation

/// Reads the raw bytes and neighbours of a saved web page: its text encoding, its "Save Page As… Complete" folder
/// and the address it was saved from.
enum HTMLSource {
    /// Decodes a page the way browsers do: a byte-order mark wins, then a `<meta>` charset declared in the first
    /// kilobyte, then UTF-8, then windows-1252, which accepts any byte.
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]), let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return text }
        if data.starts(with: [0xFE, 0xFF]), let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return text }
        if let declared = declaredEncoding(in: data), let text = String(data: data, encoding: declared) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// The folder browsers save a page's images and styles into: `<name>_files` beside `<name>.html`.
    static func resourcesFolder(for page: URL) -> URL? {
        let name = page.deletingPathExtension().lastPathComponent
        let folder = page.deletingLastPathComponent().appendingPathComponent("\(name)_files", isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue ? folder : nil
    }

    /// The address in the `<!-- saved from url=(0035)https://… -->` comment Chrome writes at the top of a saved page.
    static func savedFromURL(in html: String) -> URL? {
        let head = String(html.prefix(2048))
        guard let match = head.firstMatch(of: /saved from url=\(\d+\)(\S+)/) else { return nil }
        return URL(string: String(match.1).replacingOccurrences(of: "%2D", with: "-"))
    }

    /// The contents of each `<script type="application/ld+json">`. The extraction view runs without page scripts,
    /// and WebKit then drops script elements from the DOM, so these are read from the markup itself.
    static func jsonLDBlocks(in html: String) -> [String] {
        html.matches(of: /(?is)<script\b[^>]*\btype\s*=\s*["']?application\/ld\+json["']?[^>]*>(.*?)<\/script\s*>/)
            .map { String($0.1).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func declaredEncoding(in data: Data) -> String.Encoding? {
        let prefix = String(decoding: data.prefix(1024), as: UTF8.self)
        guard let match = prefix.firstMatch(of: /(?i)charset\s*=\s*["']?\s*([A-Za-z0-9_\-:.]+)/) else { return nil }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(String(match.1) as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}
