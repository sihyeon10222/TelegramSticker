import Foundation

nonisolated struct LibraryReader: Sendable {
    static let appGroup = "group.com.sihyeon.TelegramSticker"
    let root: URL
    private let rootPath: String

    init(root: URL) {
        self.root = root.standardizedFileURL
        self.rootPath = self.root.path
    }

    static func shared() throws -> LibraryReader {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw LibraryError.unavailable
        }
        return LibraryReader(root: container.appendingPathComponent("StickerLibrary", isDirectory: true))
    }

    private static func validateRelativePath(_ relative: String) throws {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.hasPrefix("/"), parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0")
        }) else { throw LibraryError.unsafePath }
    }

    /// Rejects traversal and every existing symlink component, including the root.
    func file(_ relative: String) throws -> URL {
        var checkedDirectories = Set<String>()
        return try file(relative, checkedDirectories: &checkedDirectories)
    }

    /// Validation is shared only within one synchronous snapshot, never across revisions.
    /// Every leaf is still checked; only existing safe parent directories are reused.
    func file(_ relative: String, checkedDirectories: inout Set<String>) throws -> URL {
        try Self.validateRelativePath(relative)
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        if !checkedDirectories.contains(rootPath) {
            guard root.resolvingSymlinksInPath().path == rootPath else { throw LibraryError.unsafePath }
            checkedDirectories.insert(rootPath)
        }
        var path = rootPath
        for part in parts {
            path += "/" + part
            if !checkedDirectories.contains(path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                let type = attrs[.type] as? FileAttributeType
                if type == .typeSymbolicLink { throw LibraryError.unsafePath }
                if type == .typeDirectory { checkedDirectories.insert(path) }
            }
        }
        return URL(fileURLWithPath: path)
    }

    static func safeID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 100 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    func index() throws -> LibraryIndexV1 {
        var checkedDirectories = Set<String>()
        return try index(checkedDirectories: &checkedDirectories)
    }

    private func index(checkedDirectories: inout Set<String>) throws -> LibraryIndexV1 {
        let url = try file("index.json", checkedDirectories: &checkedDirectories)
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryIndexV1(libraryRevision: "empty") }
        let data = try boundedData(url, limit: 2 * 1_024 * 1_024)
        let index: LibraryIndexV1
        do { index = try JSONDecoder().decode(LibraryIndexV1.self, from: data) }
        catch { throw LibraryError.invalidIndex }
        guard index.schemaVersion == 1 else { throw LibraryError.unsupportedVersion }
        guard index.packs.count <= 1_000, Set(index.packs.map(\.id)).count == index.packs.count else {
            throw LibraryError.invalidIndex
        }
        for pack in index.packs {
            guard Self.safeID(pack.id), pack.manifestPath.hasPrefix("packs/\(pack.id)/"),
                  pack.manifestPath.hasSuffix("/manifest.json"),
                  pack.manifestPath.split(separator: "/").count == 4 else { throw LibraryError.invalidIndex }
            _ = try file(pack.manifestPath, checkedDirectories: &checkedDirectories)
        }
        return index
    }

    /// Metadata-only reads populate the app's first frame without stat-ing every image.
    /// Resolve and validate symlinks again through file(_:) before opening any asset.
    func snapshot(resolvingFiles: Bool = true) throws -> LibrarySnapshot {
        var checkedDirectories = Set<String>()
        let index = try index(checkedDirectories: &checkedDirectories)
        return try snapshot(index: index, resolvingFiles: resolvingFiles, checkedDirectories: &checkedDirectories)
    }

    /// Presentation reads only the index/manifests. Every asset URL still goes
    /// through file(_:) when Sticker supplies it to an image decoder or copier.
    func contents(reusing cached: LibraryContents? = nil) throws -> LibraryContents {
        try Task.checkCancellation()
        var checkedDirectories = Set<String>()
        let index = try index(checkedDirectories: &checkedDirectories)
        if let cached, cached.reader.root == root, cached.snapshot.warnings.isEmpty,
           cached.snapshot.revision == index.libraryRevision, cached.snapshot.cacheGeneration == index.cacheGeneration {
            return cached
        }
        let snapshot = try snapshot(index: index, resolvingFiles: false, checkedDirectories: &checkedDirectories)
        return LibraryContents(reader: self, snapshot: snapshot)
    }

    private func snapshot(index: LibraryIndexV1, resolvingFiles: Bool, checkedDirectories: inout Set<String>) throws -> LibrarySnapshot {
        var packs: [PackManifestV1] = []
        var warnings: [String] = []
        var files: [String: URL] = [:]
        for reference in index.packs {
            try Task.checkCancellation()
            do {
                let data = try boundedData(file(reference.manifestPath, checkedDirectories: &checkedDirectories), limit: 2 * 1_024 * 1_024)
                let pack = try JSONDecoder().decode(PackManifestV1.self, from: data)
                guard pack.schemaVersion == 1, pack.id == reference.id, Self.safeID(pack.revision),
                      reference.manifestPath == "packs/\(pack.id)/\(pack.revision)/manifest.json",
                      pack.stickers.count <= 1_000,
                      Set(pack.stickers.map(\.id)).count == pack.stickers.count else { throw LibraryError.invalidIndex }
                let prefix = "packs/\(pack.id)/\(pack.revision)/"
                if let pending = pack.pendingStickerIDs {
                    guard pending.count <= 1_000, pending.allSatisfy(Self.safeID),
                          Set(pending).count == pending.count,
                          Set(pending).isDisjoint(with: Set(pack.stickers.map(\.id))),
                          pack.originalCount == pack.stickers.count + pending.count,
                          let name = pack.telegramName, pack.id == "telegram-" + name,
                          name.range(of: "^[a-z0-9_]{1,64}$", options: .regularExpression) != nil else { throw LibraryError.invalidIndex }
                }
                for sticker in pack.stickers {
                    try Task.checkCancellation()
                    guard Self.safeID(sticker.id), sticker.format == "png",
                          sticker.pngPath.hasPrefix(prefix), sticker.thumbnailPath.hasPrefix(prefix) else {
                        throw LibraryError.unsafePath
                    }
                    try Self.validateRelativePath(sticker.pngPath)
                    try Self.validateRelativePath(sticker.thumbnailPath)
                    if resolvingFiles {
                        files[sticker.pngPath] = try file(sticker.pngPath, checkedDirectories: &checkedDirectories)
                        files[sticker.thumbnailPath] = try file(sticker.thumbnailPath, checkedDirectories: &checkedDirectories)
                    }
                    if let playback = sticker.playbackPath {
                        guard playback.hasPrefix(prefix), playback.hasSuffix(".gif") else { throw LibraryError.unsafePath }
                        try Self.validateRelativePath(playback)
                        if resolvingFiles { files[playback] = try file(playback, checkedDirectories: &checkedDirectories) }
                    }
                    if let animation = sticker.animationPath {
                        guard animation.hasPrefix(prefix), animation.hasSuffix(".gif") else { throw LibraryError.unsafePath }
                        try Self.validateRelativePath(animation)
                        if resolvingFiles { files[animation] = try file(animation, checkedDirectories: &checkedDirectories) }
                    }
                }
                packs.append(pack)
            } catch is CancellationError { throw CancellationError() }
            catch {
                warnings.append("일부 팩을 읽을 수 없어요. 메인 앱에서 해당 팩을 확인해 주세요.")
            }
        }
        return LibrarySnapshot(revision: index.libraryRevision, packs: packs, warnings: warnings,
            cacheGeneration: index.cacheGeneration, files: files, references: index.packs)
    }

    func boundedData(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= limit else {
            throw LibraryError.invalidIndex
        }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw LibraryError.invalidIndex }
        return data
    }
}

/// Each process keeps its own read-only cache for asynchronous refreshes.
/// The app and keyboard supply their initial metadata read to avoid reading
/// manifests again when the index still describes the same publication.
actor LibrarySnapshotLoader {
    static let shared = LibrarySnapshotLoader()
    private var cached: LibraryContents?

    func loadShared(force: Bool = false, reusing initial: LibraryContents? = nil) throws -> LibraryContents {
        try load(reader: LibraryReader.shared(), force: force, reusing: initial)
    }

    func load(reader: LibraryReader, force: Bool = false, reusing initial: LibraryContents? = nil) throws -> LibraryContents {
        let previous = initial?.reader.root == reader.root ? initial : cached
        let contents = try reader.contents(reusing: force ? nil : previous)
        cached = contents
        return contents
    }
}
