import Foundation

/// Only app-owned caches and optimization drafts. Framework-managed SQLite/URLSession
/// temporary files must stay under their owner's lifecycle, even inside our sandbox.
nonisolated enum AppDisposableCache {
    static var roots: [URL] {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).flatMap { directory in
            ["GalleryPreviews", "PackUpdateChecks"].map { directory.appendingPathComponent($0, isDirectory: true) }
        }
        let temporary = (try? fm.contentsOfDirectory(at: fm.temporaryDirectory,
            includingPropertiesForKeys: nil)) ?? []
        let drafts = temporary.filter {
            $0.lastPathComponent.hasPrefix("StickerOptimization-") &&
                UUID(uuidString: String($0.lastPathComponent.dropFirst("StickerOptimization-".count))) != nil
        }
        return caches + drafts
    }
    static func bytes() -> Int64 {
        roots.reduce(Int64(URLCache.shared.currentDiskUsage)) { $0 + bytes(at: $1) }
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
        var failure: Error?
        for root in roots {
            let path = root.standardizedFileURL.resolvingSymlinksInPath().path
            let keep = preserving.contains { protected in
                let protectedPath = protected.standardizedFileURL.resolvingSymlinksInPath().path
                return protectedPath == path || protectedPath.hasPrefix(path + "/")
            }
            guard !keep else { continue }
            do {
                guard fm.fileExists(atPath: root.path) else { continue }
                guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.unsafePath }
                try fm.removeItem(at: root)
            } catch {
                // URLSession, maintenance or draft disposal may already have removed it.
                let cocoa = error as NSError
                if cocoa.domain == NSCocoaErrorDomain,
                   cocoa.code == NSFileNoSuchFileError || cocoa.code == NSFileReadNoSuchFileError { continue }
                // Still clean the other owned caches and report genuine failures.
                if failure == nil { failure = error }
            }
        }
        if let failure { throw failure }
    }
}
