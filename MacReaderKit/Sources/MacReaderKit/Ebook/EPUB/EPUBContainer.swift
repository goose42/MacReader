import Foundation

/// The files of a book, whether it is a `.epub` archive or the unpacked folder Apple Books keeps.
struct EPUBContainer: Sendable {
    enum Failure: Error, Equatable {
        case notAnEPUB
        case missing(String)
    }

    private enum Storage: Sendable {
        case archive(ZipArchive)
        case folder(URL)
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    init(data: Data) throws {
        guard let archive = try? ZipArchive(data: data) else { throw Failure.notAnEPUB }
        self.init(storage: .archive(archive))
    }

    init(contentsOf url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            self.init(storage: .folder(url.resolvingSymlinksInPath()))
        } else {
            try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
        }
    }

    func contains(_ path: String) -> Bool {
        switch storage {
        case .archive(let archive): archive.contains(path)
        case .folder(let root): Self.file(at: path, in: root) != nil
        }
    }

    func data(at path: String) throws -> Data {
        switch storage {
        case .archive(let archive):
            do { return try archive.data(for: path) } catch ZipArchive.Failure.missingEntry { throw Failure.missing(path) }
        case .folder(let root):
            guard let file = Self.file(at: path, in: root), let data = try? Data(contentsOf: file) else { throw Failure.missing(path) }
            return data
        }
    }

    /// Where the package document (the OPF) is, as `META-INF/container.xml` says.
    func packagePath() throws -> String {
        guard contains("META-INF/container.xml"),
              let root = try? XMLTree.parse(try data(at: "META-INF/container.xml"))
        else { throw Failure.notAnEPUB }
        let rootfiles = root.descendants(named: "rootfile")
        let chosen = rootfiles.first { $0.attributes["media-type"] == "application/oebps-package+xml" } ?? rootfiles.first
        guard let address = chosen?.attributes["full-path"],
              let path = EPUBPath.resolve(address, relativeTo: ""), contains(path)
        else { throw Failure.notAnEPUB }
        return path
    }

    /// The file for `path` in a folder, provided it is a regular file that really sits inside it.
    private static func file(at path: String, in root: URL) -> URL? {
        let url = root.appendingPathComponent(path).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard url.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
        else { return nil }
        return url
    }
}
