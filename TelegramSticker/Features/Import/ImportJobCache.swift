import Foundation

/// Only the latest attempted pack is retained. A lease prevents overlapping sheets from
/// deleting another import's files while its cancelled child tasks are still finishing.
actor ImportJobCache {
    static let shared = ImportJobCache()
    private var activeRoots = Set<String>()

    func begin(root: URL, key: String) throws -> URL {
        let root = root.standardizedFileURL
        guard !activeRoots.contains(root.path) else { throw StickerImportError.importInProgress }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw StickerImportError.invalidResponse
        }
        let directory = root.appendingPathComponent(key, isDirectory: true)
        for entry in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            // Leave draft metadata and unknown files alone. Only remove our hash-named jobs.
            guard entry.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { continue }
            let isLink = try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
            if entry.lastPathComponent != key || isLink { try fm.removeItem(at: entry) }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        activeRoots.insert(root.path)
        return directory
    }

    func isActive(root: URL) -> Bool { activeRoots.contains(root.standardizedFileURL.path) }
    func clear(root: URL, writer: LibraryWriter) async throws {
        let key = root.standardizedFileURL.path
        guard !activeRoots.contains(key) else { throw StickerImportError.importInProgress }
        activeRoots.insert(key)
        defer { activeRoots.remove(key) }
        try await clearLeased(root: root, writer: writer, preserving: [])
    }

    private func clearLeased(root: URL, writer: LibraryWriter, preserving: Set<URL>) async throws {
        await GalleryPreviewStore.shared.beginMaintenance()
        do {
            try await writer.clearDisposableData()
            let fm = FileManager.default
            if fm.fileExists(atPath: root.path) {
                // This entire directory belongs to resumable imports, including nested batch jobs.
                for entry in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                    try fm.removeItem(at: entry)
                }
            }
            try AppDisposableCache.clear(preserving: preserving)

            await GalleryPreviewStore.shared.endMaintenance()
        } catch {
            await GalleryPreviewStore.shared.endMaintenance()
            throw error
        }
    }

    func deleteInstalledData(root: URL, writer: LibraryWriter) async throws {
        let key = root.standardizedFileURL.path
        guard !activeRoots.contains(key) else { throw StickerImportError.importInProgress }
        activeRoots.insert(key)
        defer { activeRoots.remove(key) }
        try await writer.resetLibrary()
    }

    func reset(root: URL, writer: LibraryWriter) async throws {
        let key = root.standardizedFileURL.path
        guard activeRoots.isEmpty else { throw StickerImportError.importInProgress }
        activeRoots.insert(key)
        defer { activeRoots.remove(key) }
        await GalleryPreviewStore.shared.beginMaintenance()
        do {
            try await writer.resetLibrary()
            try AppDisposableCache.clear()
            let fm = FileManager.default
            for directory in fm.urls(for: .applicationSupportDirectory, in: .userDomainMask) + fm.urls(for: .documentDirectory, in: .userDomainMask) {
                if fm.fileExists(atPath: directory.path) {
                    for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) { try fm.removeItem(at: file) }
                }
            }
            if let url = KeyboardAccessReceipt.url, fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            await GalleryMetadataStore.shared.clear()
            await GalleryPreviewStore.shared.endMaintenance()
        } catch {
            await GalleryPreviewStore.shared.endMaintenance()
            throw error
        }
    }

    func optimize(root: URL, writer: LibraryWriter, packIDs: Set<String>? = nil, stickerIDs: Set<String>? = nil, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> StorageOptimizationResult {
        let key = root.standardizedFileURL.path
        guard !activeRoots.contains(key) else { throw StickerImportError.importInProgress }
        activeRoots.insert(key)
        defer { activeRoots.remove(key) }
        var result = try await writer.optimizeStorage(packIDs: packIDs, stickerIDs: stickerIDs, progress: progress)
        do { try await clearLeased(root: root, writer: writer, preserving: []) }
        catch { result.failures.append("용량 최적화는 반영했지만 일부 캐시 정리에 실패했어요: " + error.localizedDescription) }
        return result
    }

    func end(root: URL) { activeRoots.remove(root.standardizedFileURL.path) }
}
