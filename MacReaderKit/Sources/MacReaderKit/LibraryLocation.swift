import Foundation

/// Persists the user's chosen library folder as a security-scoped bookmark so access survives relaunch under the sandbox.
public struct LibraryLocation {
    private static let key = "libraryFolderBookmark"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.key)
    }

    /// The saved folder, or nil if none was saved or it no longer exists. Refreshes stale bookmarks.
    /// Callers must balance with `startAccessingSecurityScopedResource()` on the returned URL.
    public func resolve() -> URL? {
        guard let bookmark = defaults.data(forKey: Self.key) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        if isStale { try? save(url) }
        return url
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
