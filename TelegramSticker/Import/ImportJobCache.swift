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
        try await writer.clearDisposableData()
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if entry.lastPathComponent == "draft.json" || entry.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil {
                try fm.removeItem(at: entry)
            }
        }
    }

    func prepareOptimization(root: URL, writer: LibraryWriter, packIDs: Set<String>?, stickerIDs: Set<String>?, profile: StorageOptimizationProfile,
                             progress: @escaping @Sendable (Int, Int) -> Void) async throws -> PreparedOptimization {
        let key = root.standardizedFileURL.path
        guard !activeRoots.contains(key) else { throw StickerImportError.importInProgress }
        activeRoots.insert(key)
        defer { activeRoots.remove(key) }
        return try await writer.prepareOptimization(packIDs: packIDs, stickerIDs: stickerIDs, profile: profile, progress: progress)
    }
    func applyOptimization(root: URL, writer: LibraryWriter, draft: PreparedOptimization,
                           progress: @escaping @Sendable (Int, Int) -> Void) async throws -> StorageOptimizationResult {
        let key = root.standardizedFileURL.path
        guard !activeRoots.contains(key) else { throw StickerImportError.importInProgress }
        activeRoots.insert(key)
        defer { activeRoots.remove(key) }
        return try await writer.applyOptimization(draft, progress: progress)
    }

    func optimize(root: URL, writer: LibraryWriter, packIDs: Set<String>? = nil, stickerIDs: Set<String>? = nil, profile: StorageOptimizationProfile = .balanced, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> StorageOptimizationResult {
        let key = root.standardizedFileURL.path
        guard !activeRoots.contains(key) else { throw StickerImportError.importInProgress }
        activeRoots.insert(key)
        defer { activeRoots.remove(key) }
        return try await writer.optimizeStorage(packIDs: packIDs, stickerIDs: stickerIDs, profile: profile, progress: progress)
    }

    func end(root: URL) { activeRoots.remove(root.standardizedFileURL.path) }
}
