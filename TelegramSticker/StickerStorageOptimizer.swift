import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum StorageOptimizationProfile: String, CaseIterable, Identifiable, Sendable, Hashable {
    case compact, balanced
    var id: String { rawValue }
    var pixels: Int { self == .balanced ? 384 : 256 }
    var fps: Int { self == .balanced ? 24 : 15 }
    var title: String { self == .balanced ? "화질 우선" : "용량 우선" }
    var label: String { "용량 최적화 · \(pixels)px · 최대 \(fps)fps" }
}
nonisolated enum StorageOptimizationError: Error { case noSavings }
nonisolated struct StorageOptimizationResult: Sendable {
    var saved: Int64 = 0
    var optimizedPacks = 0
    var failures: [String] = []
}

nonisolated enum StickerStorageOptimizer {
    static let label = StorageOptimizationProfile.balanced.label
    static func bytes(_ url: URL) throws -> Int64 {
        let fm = FileManager.default
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw LibraryError.unsafePath }
        if values.isDirectory != true { return Int64(values.fileSize ?? 0) }
        return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).reduce(0) { try $0 + bytes($1) }
    }
    static func png(from url: URL, to output: URL, pixels: Int = 384) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCache: false
              ] as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw LibraryError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), PNGValidation.isValid(try Data(contentsOf: output)) else { throw LibraryError.invalidImage }
    }
}

extension LibraryWriter {
    /// No await: publication, deletion, updates and optimization cannot race this transaction.
    func optimizeStorage(packIDs: Set<String>? = nil, stickerIDs: Set<String>? = nil, profile: StorageOptimizationProfile = .balanced, retainOldRevisions: Bool = false, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> StorageOptimizationResult {
        let snapshot = try reader.snapshot()
        guard snapshot.warnings.isEmpty else { throw LibraryError.invalidIndex }
        var result = StorageOptimizationResult()
        let packs = snapshot.packs.filter { packIDs == nil || packIDs!.contains($0.id) }
        let total = packs.reduce(0) { sum, pack in sum + pack.stickers.filter { stickerIDs == nil || stickerIDs!.contains(pack.id + "." + $0.id) }.count }
        var completed = 0
        progress(0, total)
        for pack in packs {
            try Task.checkCancellation()
            guard !pack.stickers.isEmpty else { continue }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let packEnd = completed + pack.stickers.filter { stickerIDs == nil || stickerIDs!.contains(pack.id + "." + $0.id) }.count
            defer { completed = packEnd; progress(completed, total) }
            do {
                let oldDirectory = try reader.file("packs/\(pack.id)/\(pack.revision)")
                let before = try StickerStorageOptimizer.bytes(oldDirectory)
                var inputs: [LocalStickerInput] = []
                var changed = false
                for sticker in pack.stickers {
                    try Task.checkCancellation()
                    let eligible = stickerIDs == nil || stickerIDs!.contains(pack.id + "." + sticker.id)
                    defer { if eligible { completed += 1; progress(completed, total) } }
                    try autoreleasepool {
                    let oldPNG = try reader.file(sticker.pngPath)
                    var png = oldPNG
                    var gif = try sticker.animationPath.map { try reader.file($0) }
                    var quality = sticker.conversionQuality
                    if eligible && quality?.hasPrefix(profile.label) != true {
                        let candidate = temporary.appendingPathComponent(sticker.id + ".png")
                        try StickerStorageOptimizer.png(from: oldPNG, to: candidate, pixels: profile.pixels)
                        var smaller = false
                        var keptOriginal = false
                        if try StickerStorageOptimizer.bytes(candidate) < StickerStorageOptimizer.bytes(oldPNG) { png = candidate; smaller = true } else { keptOriginal = true }
                        if let original = gif {
                            let candidateGIF = temporary.appendingPathComponent(sticker.id + ".gif")
                            try KeyboardPlaybackBuilder.build(from: original, to: candidateGIF, pixels: profile.pixels, fps: profile.fps)
                            if try StickerStorageOptimizer.bytes(candidateGIF) < StickerStorageOptimizer.bytes(original) { gif = candidateGIF; smaller = true } else { keptOriginal = true }
                        }
                        if smaller { changed = true; quality = profile.label + (keptOriginal ? " · 일부 원본 유지" : "") }
                    }
                    inputs.append(LocalStickerInput(id: sticker.id, name: sticker.name, url: png,
                        sourceFormat: sticker.sourceFormat ?? "png", animationURL: gif, conversionQuality: quality))
                    }
                }
                guard changed else { continue }
                try install(id: pack.id, title: pack.title, stickers: inputs, originalCount: pack.originalCount,
                    telegramName: pack.telegramName, pendingStickerIDs: pack.pendingStickerIDs,
                    replacingRevision: pack.revision, lastCheckedAt: pack.lastCheckedAt, maximumStoredBytes: before)
                guard let current = try self.pack(id: pack.id) else { throw LibraryError.invalidIndex }
                let after = try StickerStorageOptimizer.bytes(reader.file("packs/\(pack.id)/\(current.revision)"))
                // Only the replaced revision is disposable; installed assets remain available offline.
                result.optimizedPacks += 1
                do {
                    if !retainOldRevisions { try FileManager.default.removeItem(at: oldDirectory) }
                    result.saved += max(0, before - after)
                } catch {
                    result.failures.append("\(pack.title): 용량 최적화는 완료했지만 이전 파일을 정리하지 못했어요. 캐시 삭제로 다시 정리해 주세요.")
                }
            } catch is CancellationError { throw CancellationError() }
            catch StorageOptimizationError.noSavings { continue }
            catch { result.failures.append("\(pack.title): \(error.localizedDescription)") }
        }
        return result
    }
}

nonisolated struct OptimizationComparison: Identifiable, Sendable {
    let id: String
    let original: SampleSticker
    let optimized: SampleSticker
    let before: Int64
    let after: Int64
}
nonisolated struct PreparedOptimization: Sendable {
    let root: URL
    let originals: [PackManifestV1]
    let comparisons: [OptimizationComparison]
    let before: Int64
    let after: Int64
    let failures: [String]
    var saved: Int64 { max(0, before - after) }
}

extension LibraryWriter {
    /// Prepare against an isolated copy. No installed revision or clipboard is changed.
    func prepareOptimization(packIDs: Set<String>?, stickerIDs: Set<String>?, profile: StorageOptimizationProfile,
                             progress: @escaping @Sendable (Int, Int) -> Void) async throws -> PreparedOptimization {
        let snapshot = try reader.snapshot()
        guard snapshot.warnings.isEmpty else { throw LibraryError.invalidIndex }
        let originals = snapshot.packs.filter { packIDs == nil || packIDs!.contains($0.id) }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StickerOptimization-" + UUID().uuidString)
        let shadowReader = LibraryReader(root: root), fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var prepared = false
        defer { if !prepared { try? fm.removeItem(at: root) } }
        var index = try reader.index()
        index.packs = index.packs.filter { ref in originals.contains { $0.id == ref.id } }
        var before: Int64 = 0
        for pack in originals {
            try Task.checkCancellation()
            let relative = "packs/\(pack.id)/\(pack.revision)"
            let source = try reader.file(relative), destination = try shadowReader.file(relative)
            before += try StickerStorageOptimizer.bytes(source)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
        }
        try JSONEncoder().encode(index).write(to: shadowReader.file("index.json"), options: .atomic)
        let shadowWriter = LibraryWriter(reader: shadowReader)
        let result = try await shadowWriter.optimizeStorage(packIDs: packIDs, stickerIDs: stickerIDs, profile: profile, retainOldRevisions: true, progress: progress)
        try Task.checkCancellation()
        let optimized = try shadowReader.snapshot().packs
        var comparisons: [OptimizationComparison] = []
        var after: Int64 = 0
        for pack in optimized {
            after += try StickerStorageOptimizer.bytes(shadowReader.file("packs/\(pack.id)/\(pack.revision)"))
            guard let original = originals.first(where: { $0.id == pack.id }) else { continue }
            for sticker in pack.stickers {
                try Task.checkCancellation()
                let id = pack.id + "." + sticker.id
                guard stickerIDs == nil || stickerIDs!.contains(id), let old = original.stickers.first(where: { $0.id == sticker.id }) else { continue }
                let oldPNG = try shadowReader.file(old.pngPath), newPNG = try shadowReader.file(sticker.pngPath)
                let oldGIF = try old.animationPath.map { try shadowReader.file($0) }, newGIF = try sticker.animationPath.map { try shadowReader.file($0) }
                let oldBytes = try StickerStorageOptimizer.bytes(oldPNG) + (try oldGIF.map { try StickerStorageOptimizer.bytes($0) } ?? 0)
                let newBytes = try StickerStorageOptimizer.bytes(newPNG) + (try newGIF.map { try StickerStorageOptimizer.bytes($0) } ?? 0)
                comparisons.append(OptimizationComparison(id: id,
                    original: SampleSticker(id: id + ".original", name: sticker.name, detail: original.title, imageURL: oldPNG, animationURL: oldGIF),
                    optimized: SampleSticker(id: id + ".optimized", name: sticker.name, detail: pack.title, imageURL: newPNG, animationURL: newGIF), before: oldBytes, after: newBytes))
            }
        }
        prepared = true
        return PreparedOptimization(root: root, originals: originals, comparisons: comparisons, before: before, after: after, failures: result.failures)
    }

    func applyOptimization(_ draft: PreparedOptimization, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> StorageOptimizationResult {
        let shadow = LibraryReader(root: draft.root)
        let packs = try shadow.snapshot().packs
        var result = StorageOptimizationResult(failures: draft.failures)
        for (offset, original) in draft.originals.enumerated() {
            try Task.checkCancellation()
            defer { progress(offset + 1, draft.originals.count) }
            guard let optimized = packs.first(where: { $0.id == original.id }), optimized.revision != original.revision else { continue }
            do {
                guard try hasRevision(id: original.id, revision: original.revision) else { throw LibraryError.invalidOrder }
                let oldDirectory = try reader.file("packs/\(original.id)/\(original.revision)")
                let before = try StickerStorageOptimizer.bytes(oldDirectory)
                let inputs = try optimized.stickers.map { record in
                    LocalStickerInput(id: record.id, name: record.name, url: try shadow.file(record.pngPath), sourceFormat: record.sourceFormat ?? "png",
                        animationURL: try record.animationPath.map { try shadow.file($0) }, conversionQuality: record.conversionQuality)
                }
                try install(id: original.id, title: original.title, stickers: inputs, originalCount: original.originalCount,
                    telegramName: original.telegramName, pendingStickerIDs: original.pendingStickerIDs,
                    replacingRevision: original.revision, lastCheckedAt: original.lastCheckedAt, maximumStoredBytes: before)
                guard let current = try pack(id: original.id) else { throw LibraryError.invalidIndex }
                let after = try StickerStorageOptimizer.bytes(reader.file("packs/\(current.id)/\(current.revision)"))
                result.optimizedPacks += 1
                do { try FileManager.default.removeItem(at: oldDirectory); result.saved += max(0, before - after) }
                catch { result.failures.append("\(original.title): 이전 파일 정리 실패. 캐시 삭제로 다시 정리해 주세요.") }
            } catch StorageOptimizationError.noSavings { continue }
            catch is CancellationError { throw CancellationError() }
            catch { result.failures.append("\(original.title): \(error.localizedDescription)") }
        }
        return result
    }
}
