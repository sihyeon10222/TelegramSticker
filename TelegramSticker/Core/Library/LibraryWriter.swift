import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

nonisolated struct LocalStickerInput: Sendable {
    let id: String
    let name: String
    let url: URL
    var sourceFormat: String = "png"
    var animationURL: URL? = nil
    var conversionQuality: String? = nil
}

/// The app's only writer. Operations contain no suspension points, so publication is serialized.
actor LibraryWriter {
    @MainActor static let shared: LibraryWriter? = try? LibraryWriter(reader: LibraryReader.shared(), changeJournal: LibraryChangeJournal.directory)
    let reader: LibraryReader
    private let changeJournal: URL?
    private let publish: @Sendable (Data, URL) throws -> Void

    init(reader: LibraryReader, changeJournal: URL? = nil, publish: @escaping @Sendable (Data, URL) throws -> Void = {
        try $0.write(to: $1, options: .atomic)
    }) {
        self.reader = reader
        self.changeJournal = changeJournal
        self.publish = publish
    }

    func contains(id: String) throws -> Bool {
        try reader.index().packs.contains { $0.id == id }
    }

    func pack(id: String) throws -> PackManifestV1? {
        guard try contains(id: id) else { return nil }
        guard let pack = try reader.snapshot().packs.first(where: { $0.id == id }) else { throw LibraryError.invalidIndex }
        return pack
    }

    func hasRevision(id: String, revision: String) throws -> Bool {
        try reader.index().packs.contains { $0.id == id && $0.manifestPath == "packs/\(id)/\(revision)/manifest.json" }
    }

    func reusableStickerIDs(in pack: PackManifestV1) throws -> Set<String> {
        var result = Set<String>()
        for record in pack.stickers {
            try Task.checkCancellation()
            let valid = autoreleasepool {
                guard let url = try? reader.file(record.pngPath), let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                      PNGValidation.isValid(data),
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == record.sha256 else { return false }
                if let animation = record.animationPath {
                    guard let url = try? reader.file(animation), GIFValidation.isValid(url: url) else { return false }
                }
                return true
            }
            if valid { result.insert(record.id) }
        }
        return result
    }

    func inputs(for pack: PackManifestV1) throws -> [LocalStickerInput] {
        try pack.stickers.map { record in
            LocalStickerInput(id: record.id, name: record.name, url: try reader.file(record.pngPath),
                sourceFormat: record.sourceFormat ?? "png", animationURL: try record.animationPath.map { try reader.file($0) }, conversionQuality: record.conversionQuality)
        }
    }

    func install(id: String, title: String, stickers: [LocalStickerInput], originalCount: Int? = nil,
                 telegramName: String? = nil, pendingStickerIDs: [String]? = nil,
                 replacingRevision: String? = nil, mirroringRemote: Bool = false, lastCheckedAt: Date? = nil, maximumStoredBytes: Int64? = nil, syncOrigin: Bool = false) throws {
        guard LibraryReader.safeID(id), (!stickers.isEmpty || mirroringRemote), stickers.count <= 1_000,
              !title.isEmpty, title.count <= 256,
              (stickers.count...1_000).contains(originalCount ?? stickers.count),
              stickers.allSatisfy({ LibraryReader.safeID($0.id) && $0.name.count <= 256 }),
              Set(stickers.map(\.id)).count == stickers.count else { throw LibraryError.invalidIndex }
        var index = try reader.index()
        let position = index.packs.firstIndex { $0.id == id }
        if let expected = replacingRevision {
            guard let previous = try pack(id: id), previous.revision == expected,
                  previous.telegramName == telegramName,
                  (mirroringRemote || Set(stickers.map(\.id)).isSuperset(of: Set(previous.stickers.map(\.id)))) else { throw LibraryError.invalidOrder }
        } else if position != nil { throw LibraryError.duplicatePack }
        if let pending = pendingStickerIDs {
            guard let name = telegramName, StickerLink.validName(name), name == name.lowercased(), id == "telegram-" + name,
                  pending.allSatisfy(LibraryReader.safeID), Set(pending).count == pending.count,
                  Set(pending).isDisjoint(with: Set(stickers.map(\.id))),
                  originalCount == stickers.count + pending.count else { throw LibraryError.invalidIndex }
        }
        let revision = UUID().uuidString
        let staging = try reader.file("staging/\(revision)")
        let destination = try reader.file("packs/\(id)/\(revision)")
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var records: [StickerRecord] = []
        var totalBytes = 0
        for sticker in stickers {
            try Task.checkCancellation()
            let data = try Data(contentsOf: sticker.url, options: .mappedIfSafe)
            guard PNGValidation.isValid(data) else { throw LibraryError.invalidImage }
            totalBytes += data.count
            try data.write(to: staging.appendingPathComponent("\(sticker.id)-original.png"))
            let thumbnail = try Self.thumbnail(data)
            totalBytes += thumbnail.count
            try thumbnail.write(to: staging.appendingPathComponent("\(sticker.id)-thumb.png"))
            let prefix = "packs/\(id)/\(revision)/"
            var animationPath: String?
            if let url = sticker.animationURL {
                guard GIFValidation.isValid(url: url) else { throw LibraryError.invalidImage }
                try fm.copyItem(at: url, to: staging.appendingPathComponent("\(sticker.id)-animation.gif"))
                try KeyboardPlaybackBuilder.build(from: url, to: staging.appendingPathComponent("\(sticker.id)-playback.gif"))
                animationPath = prefix + "\(sticker.id)-animation.gif"
            }
            records.append(StickerRecord(id: sticker.id, name: sticker.name, format: "png",
                                         pngPath: prefix + "\(sticker.id)-original.png",
                                         thumbnailPath: prefix + "\(sticker.id)-thumb.png",
                                         sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                                         sourceFormat: sticker.sourceFormat, animationPath: animationPath,
                                         playbackPath: animationPath == nil ? nil : prefix + "\(sticker.id)-playback.gif",
                                         conversionQuality: sticker.conversionQuality))
        }
        let manifest = PackManifestV1(id: id, title: title, revision: revision,
                                      originalCount: originalCount ?? stickers.count, stickers: records,
                                      telegramName: telegramName, pendingStickerIDs: pendingStickerIDs, lastCheckedAt: lastCheckedAt)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"))
        if let maximumStoredBytes, try StickerStorageOptimizer.bytes(staging) >= maximumStoredBytes {
            throw StorageOptimizationError.noSavings
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: destination)
        // If this last write fails, the previous index still points only at complete packs.
        do {
            try Task.checkCancellation()
            let reference = PackReference(id: id, manifestPath: "packs/\(id)/\(revision)/manifest.json")
            if let position { index.packs[position] = reference }
            else { index.packs.append(reference) }
            let event: LibraryChange? = position == nil && !syncOrigin && telegramName != nil
                ? LibraryChange(kind: .install, packID: id, telegramName: telegramName, title: title) : nil
            try save(index, change: event)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    func preparePlaybackFiles() throws {
        for pack in try reader.snapshot().packs where pack.stickers.contains(where: { $0.animationPath != nil && $0.playbackPath == nil }) {
            try Task.checkCancellation()
            try install(id: pack.id, title: pack.title, stickers: inputs(for: pack), originalCount: pack.originalCount,
                telegramName: pack.telegramName, pendingStickerIDs: pack.pendingStickerIDs,
                replacingRevision: pack.revision, lastCheckedAt: pack.lastCheckedAt)
        }
    }

    func clearDisposableData() throws {
        // Read/validate before any deletion. Never infer unused assets from a corrupt index.
        let snapshot = try reader.snapshot()
        guard snapshot.warnings.isEmpty else { throw LibraryError.invalidIndex }
        var index = try reader.index()
        let fm = FileManager.default
        let keep = Set(index.packs.map { String($0.manifestPath.dropLast("/manifest.json".count)) })
        let packs = try reader.file("packs")
        for pack in (try? fm.contentsOfDirectory(at: packs, includingPropertiesForKeys: nil)) ?? [] {
            for revision in (try? fm.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil)) ?? [] {
                let relative = "packs/\(pack.lastPathComponent)/\(revision.lastPathComponent)"
                _ = try reader.file(relative)
                if !keep.contains(relative) { try fm.removeItem(at: revision) }
            }
        }
        let staging = try reader.file("staging")
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        index.cacheGeneration = UUID().uuidString
        // Keep libraryRevision unchanged: lists/descriptors do not need rebuilding.
        try publish(JSONEncoder().encode(index), reader.file("index.json"))
    }

    func resetLibrary() throws {
        // Publish the empty library first. A retained keyboard never sees half a deleted index.
        try FileManager.default.createDirectory(at: reader.root, withIntermediateDirectories: true)
        var index = LibraryIndexV1()
        index.cacheGeneration = UUID().uuidString
        try publish(JSONEncoder().encode(index), reader.file("index.json"))
        for name in ["packs", "staging"] {
            let url = try reader.file(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    func deleteStickers(packID: String, revision: String, ids: Set<String>) throws {
        guard let pack = try pack(id: packID), pack.revision == revision else { throw LibraryError.invalidIndex }
        guard !ids.isEmpty, ids.isSubset(of: Set(pack.stickers.map(\.id))) else { throw LibraryError.invalidIndex }
        let remaining = try inputs(for: pack).filter { !ids.contains($0.id) }
        try install(id: pack.id, title: pack.title, stickers: remaining,
                    originalCount: remaining.count + (pack.pendingStickerIDs?.count ?? 0), telegramName: pack.telegramName,
                    pendingStickerIDs: pack.pendingStickerIDs, replacingRevision: revision, mirroringRemote: true,
                    lastCheckedAt: pack.lastCheckedAt)
    }

    func delete(id: String, syncOrigin: Bool = false) throws {
        var index = try reader.index()
        guard LibraryReader.safeID(id) else { throw LibraryError.unsafePath }
        if !index.packs.contains(where: { $0.id == id }) {
            if !syncOrigin, id.hasPrefix("telegram-"), LibraryChangeJournal.enabled {
                try save(index, change: LibraryChange(kind: .delete, packID: id))
            }
            return
        }
        index.packs.removeAll { $0.id == id }
        try save(index, change: syncOrigin ? nil : LibraryChange(kind: .delete, packID: id))
        // Readers holding the old revision recover from missing files by reloading their snapshot.
        if LibraryReader.safeID(id) { try? FileManager.default.removeItem(at: reader.file("packs/\(id)")) }
    }

    /// Merge against the current index inside this actor, so parallel publications
    /// cannot race a stale full-list reorder. Unrelated packs retain their order.
    func orderImported(ids: [String]) throws {
        var index = try reader.index()
        let targets = Set(ids)
        let references = Dictionary(uniqueKeysWithValues: index.packs.map { ($0.id, $0) })
        var seen = Set<String>()
        let ordered = ids.filter { seen.insert($0).inserted }.compactMap { references[$0] }
        let first = index.packs.firstIndex { targets.contains($0.id) } ?? index.packs.count
        var others = index.packs.filter { !targets.contains($0.id) }
        others.insert(contentsOf: ordered, at: min(first, others.count))
        guard others.map(\.id) != index.packs.map(\.id) else { return }
        index.packs = others
        try save(index, change: LibraryChange(kind: .order, orderedIDs: others.map(\.id)))
    }

    func reorder(ids: [String], syncOrigin: Bool = false) throws {
        var index = try reader.index()
        guard ids.count == index.packs.count, Set(ids) == Set(index.packs.map(\.id)) else {
            throw LibraryError.invalidOrder
        }
        let references = Dictionary(uniqueKeysWithValues: index.packs.map { ($0.id, $0) })
        index.packs = ids.compactMap { references[$0] }
        try save(index, change: syncOrigin ? nil : LibraryChange(kind: .order, orderedIDs: ids))
    }

    /// Only collect old unreferenced revisions when a valid existing index proves they are unused.
    func recover(now: Date = Date()) throws {
        let fm = FileManager.default
        let hasIndex = fm.fileExists(atPath: try reader.file("index.json").path)
        let index = try reader.index()
        let staging = try reader.file("staging")
        for url in (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? [] {
            _ = try reader.file("staging/\(url.lastPathComponent)")
            try? fm.removeItem(at: url)
        }
        guard hasIndex else { return } // No index is not evidence that existing pack files are disposable.
        let packs = try reader.file("packs")
        for pack in (try? fm.contentsOfDirectory(at: packs, includingPropertiesForKeys: nil)) ?? [] {
            _ = try reader.file("packs/\(pack.lastPathComponent)")
            for revision in (try? fm.contentsOfDirectory(at: pack, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let relative = "packs/\(pack.lastPathComponent)/\(revision.lastPathComponent)"
                _ = try reader.file(relative)
                let referenced = index.packs.contains { $0.manifestPath == relative + "/manifest.json" }
                let modified = try revision.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if !referenced, let modified, now.timeIntervalSince(modified) > 86_400 { try? fm.removeItem(at: revision) }
            }
        }
    }

    func recoverChangeJournal() throws {
        if let changeJournal { try LibraryChangeJournal.recover(directory: changeJournal, revision: reader.index().libraryRevision) }
    }

    private func save(_ original: LibraryIndexV1, change: LibraryChange? = nil) throws {
        try recoverChangeJournal()
        var index = original
        index.libraryRevision = UUID().uuidString
        try FileManager.default.createDirectory(at: reader.root, withIntermediateDirectories: true)
        var prepared: URL?
        if let changeJournal, LibraryChangeJournal.enabled, var change {
            change.targetRevision = index.libraryRevision
            prepared = try LibraryChangeJournal.prepare(change, directory: changeJournal)
        }
        do { try publish(JSONEncoder().encode(index), reader.file("index.json")) }
        catch { if let prepared { try? FileManager.default.removeItem(at: prepared) }; throw error }
        // Publication succeeded. Journal finalization must never roll back or delete a published revision.
        LibraryChangeJournal.commit(prepared)
    }

    private static func thumbnail(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw LibraryError.invalidImage }
        let result = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            throw LibraryError.invalidImage
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw LibraryError.invalidImage }
        return result as Data
    }
}
