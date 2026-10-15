import Foundation

/// Only disposable directories in the main app sandbox. Never traverses Documents,
/// Application Support, preferences, Keychain or the installed App Group library.
nonisolated enum AppDisposableCache {
    static var roots: [URL] {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask) +
            [FileManager.default.temporaryDirectory]
    }
    static func bytes() -> Int64 {
        roots.reduce(0) { $0 + bytes(at: $1) }
    }
    static func bytes(at root: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return 0 }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    static func clear(preserving: Set<URL> = []) throws {
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.unsafePath }
            // Remove children, preserving the OS-managed directory itself.
            for entry in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                let path = entry.standardizedFileURL.resolvingSymlinksInPath().path
                let keep = preserving.contains { protected in
                    let protectedPath = protected.standardizedFileURL.resolvingSymlinksInPath().path
                    return protectedPath == path || protectedPath.hasPrefix(path + "/")
                }
                if !keep { try fm.removeItem(at: entry) }
            }
        }
    }
}
