import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum StorageOptimizationProfile: String, CaseIterable, Identifiable, Sendable, Hashable {
    case compact
    var id: String { rawValue }
    var pixels: Int { 256 }
    var fps: Int { 15 }
    var title: String { "용량 우선" }
    var label: String { "용량 최적화 · \(pixels)px · 최대 \(fps)fps" }
}
nonisolated enum StorageOptimizationError: Error { case noSavings }
nonisolated struct StorageOptimizationResult: Sendable {
    var saved: Int64 = 0
    var optimizedPacks = 0
    var failures: [String] = []
}

nonisolated enum StickerStorageOptimizer {
    static let label = StorageOptimizationProfile.compact.label
    static func bytes(_ url: URL) throws -> Int64 {
        let fm = FileManager.default
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw LibraryError.unsafePath }
        if values.isDirectory != true { return Int64(values.fileSize ?? 0) }
        return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).reduce(0) { try $0 + bytes($1) }
    }
    static func png(from url: URL, to output: URL, pixels: Int = 256) throws {
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
    func optimizeStorage(packIDs: Set<String>? = nil, stickerIDs: Set<String>? = nil, profile: StorageOptimizationProfile = .compact, retainOldRevisions: Bool = false, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> StorageOptimizationResult {
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
                    let oldGIF = gif
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
                        sourceFormat: sticker.sourceFormat ?? "png", animationURL: gif, conversionQuality: quality,
                        reusableFiles: png == oldPNG && gif == oldGIF && quality == sticker.conversionQuality
                            ? ReusableStickerFiles(reader: reader, packID: pack.id, revision: pack.revision, record: sticker) : nil))
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
