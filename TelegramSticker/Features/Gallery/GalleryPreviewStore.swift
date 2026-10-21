import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Observation
import UIKit

nonisolated struct GalleryPreviewFiles: Sendable {
    let poster: URL?
    let animation: URL?
}

@MainActor @Observable
final class GalleryPreviewState {
    static let shared = GalleryPreviewState()
    var generation = 0
    var maintaining = false
    // SwiftUI may discard a LazyVGrid card; its loaded state must outlive that view.
    private var items: [String: GalleryPreviewItem] = [:]
    private var order: [String] = []
    var metadata: [String: RemotePack] = [:]
    private struct RestoreJob { let id: UUID; let task: Task<Void, Never> }
    @ObservationIgnored private var restores: [String: RestoreJob] = [:]
    @ObservationIgnored private var restoredNames = Set<String>()
    private init() {}

    private func apply(_ cards: [GalleryCachedCard]) {
        for card in cards {
            if metadata[card.pack.name] == nil { metadata[card.pack.name] = card.pack }
            for preview in card.previews {
                item(key: GalleryPreviewStore.key(pack: card.pack.name, sticker: preview.sticker))
                    .restore(files: preview.files, poster: preview.poster)
            }
        }
    }
    /// Restore only a visible card. Concurrent requests share the same disk read.
    func restore(name: String) async {
        guard !maintaining, !restoredNames.contains(name) else { return }
        if let existing = restores[name] { await existing.task.value; return }
        let epoch = generation, id = UUID()
        let task = Task {
            defer { if restores[name]?.id == id { restores[name] = nil } }
            let cards = await Task.detached(priority: .userInitiated) { await GalleryDiskCache.read(names: [name]) }.value
            guard !Task.isCancelled, !maintaining, generation == epoch else { return }
            apply(cards)
            restoredNames.insert(name)
        }
        restores[name] = RestoreJob(id: id, task: task)
        await task.value
    }
    func item(key: String) -> GalleryPreviewItem {
        if let item = items[key] { return item }
        let item = GalleryPreviewItem()
        items[key] = item; order.append(key)
        if order.count > 600 {
            let removed = order.removeFirst()
            items.removeValue(forKey: removed)?.cancel()
        }
        return item
    }
    func cancelLoading() {
        for restore in restores.values { restore.task.cancel() }
        restores.removeAll()
        for item in items.values { item.cancel() }
    }
    func clearItems() {
        cancelLoading()
        restoredNames.removeAll()
        for item in items.values { item.clear() }
        metadata.removeAll()
    }
}

@MainActor @Observable
final class GalleryPreviewItem {
    private(set) var files: GalleryPreviewFiles?
    private(set) var poster: UIImage?
    private var task: Task<Void, Never>?
    private var token = UUID()
    private var retryAfter = Date.distantPast
    func restore(files: GalleryPreviewFiles, poster: CGImage) {
        // A delayed disk read must never overwrite newer, already loaded content.
        guard self.files == nil, task == nil else { return }
        self.poster = UIImage(cgImage: poster)
        self.files = files
    }
    func cancel() { token = UUID(); task?.cancel(); task = nil }
    func clear() { cancel(); files = nil; poster = nil; retryAfter = .distantPast }
    func load(pack: String, sticker: RemoteSticker, client: WorkerClient, animate: Bool) {
        let ready = files?.poster != nil && (!animate || sticker.format == "static" || files?.animation != nil)
        guard !ready, task == nil, Date() >= retryAfter else { return }
        let token = token
        task = Task {
            defer { if self.token == token { task = nil } }
            do {
                // Read the complete cached representation first. Never replace a GIF
                // with a poster-only result each time its card becomes visible.
                if let cached = await GalleryPreviewStore.shared.cachedFiles(pack: pack, sticker: sticker) {
                    try Task.checkCancellation()
                    guard self.token == token else { return }
                    await publish(cached, token: token)
                    if !animate || sticker.format == "static" || cached.animation != nil { return }
                }
                if files?.poster == nil {
                    let value = try await GalleryPreviewStore.shared.files(pack: pack, sticker: sticker, client: client, animate: false)
                    await publish(value, token: token)
                    if value.poster == nil, sticker.format == "static" { retryAfter = Date().addingTimeInterval(60) }
                }
                try Task.checkCancellation()
                if animate, sticker.format != "static", files?.animation == nil {
                    let value = try await GalleryPreviewStore.shared.files(pack: pack, sticker: sticker, client: client, animate: true)
                    await publish(value, token: token)
                    if value.animation == nil { retryAfter = Date().addingTimeInterval(60) }
                }
            } catch is CancellationError { return }
            catch {
                if self.token == token { retryAfter = Date().addingTimeInterval(60) }
                DownloadDiagnostics.shared.record("GALLERY_PREVIEW pack=\(pack) " + DownloadDiagnostics.errorDetails(error))
            }
        }
    }
    private func publish(_ value: GalleryPreviewFiles, token: UUID) async {
        guard self.token == token, !Task.isCancelled else { return }
        // Preserve the already decoded poster and loaded animation on revisits.
        if poster == nil, let url = value.poster {
            let image = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 96, kCGImageSourceShouldCache: false
                ] as CFDictionary)
            }.value
            guard self.token == token, !Task.isCancelled else { return }
            poster = image.map { UIImage(cgImage: $0) }
        }
        files = GalleryPreviewFiles(poster: value.poster ?? files?.poster, animation: value.animation ?? files?.animation)
    }
}

/// Preview work never registers BackgroundWork, installs packs or posts notifications.
actor GalleryPreviewStore {
    static let shared = GalleryPreviewStore()
    private struct Job { let id: UUID; let task: Task<GalleryPreviewFiles, Error> }
    private var jobs: [String: Job] = [:]
    private var visible = Set<String>()
    private var maintenance = 0
    private let downloads = RequestGate(limit: 2)
    private let conversions = RequestGate(limit: 1)
    private var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("GalleryPreviews/v1")
    }
    nonisolated static func key(pack: String, sticker: RemoteSticker) -> String {
        let value = "v1|\(pack)|\(sticker.id)|\(sticker.format)|\(sticker.fileSize ?? 0)|\(sticker.width)x\(sticker.height)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func setVisible(_ key: String, _ showing: Bool) {
        if showing { visible.insert(key) } else { visible.remove(key) }
    }
    func beginMaintenance() async {
        maintenance += 1
        await GalleryMetadataStore.shared.beginMaintenance()
        await MainActor.run {
            GalleryPreviewState.shared.maintaining = true
            GalleryPreviewState.shared.clearItems()
        }
        let pending = Array(jobs.values)
        for job in pending { job.task.cancel() }
        for job in pending { _ = try? await job.task.value }
        // Only jobs from this generation can exist while maintenance is active.
        jobs.removeAll()
        await GIFFrameDecoder.shared.clear()
    }
    func endMaintenance() async {
        maintenance = max(0, maintenance - 1)
        if maintenance == 0 {
            await GalleryMetadataStore.shared.endMaintenance()
            await MainActor.run {
                GalleryPreviewState.shared.generation += 1
                GalleryPreviewState.shared.maintaining = false
            }
        }
    }
    func cancelForForegroundWork() async {
        await beginMaintenance()
        await endMaintenance()
    }
    private func cancel(key: String, id: UUID) {
        guard jobs[key]?.id == id else { return }
        jobs[key]?.task.cancel()
    }
    func files(pack: String, sticker: RemoteSticker, client: WorkerClient, animate: Bool) async throws -> GalleryPreviewFiles {
        guard maintenance == 0 else { throw CancellationError() }
        try Task.checkCancellation()
        let key = Self.key(pack: pack, sticker: sticker)
        let jobKey = key + (animate ? ":animated" : ":poster")
        if let previous = jobs[jobKey], previous.task.isCancelled {
            _ = try? await previous.task.value
            if jobs[jobKey]?.id == previous.id { jobs[jobKey] = nil }
        }
        guard maintenance == 0 else { throw CancellationError() }
        let job: Job
        if let existing = jobs[jobKey] { job = existing }
        else {
            let id = UUID()
            let task = Task(priority: .utility) { try await self.make(pack: pack, sticker: sticker, client: client, key: key, animate: animate) }
            job = Job(id: id, task: task); jobs[jobKey] = job
        }
        return try await withTaskCancellationHandler {
            do {
                let value = try await job.task.value
                if jobs[jobKey]?.id == job.id { jobs[jobKey] = nil }
                try Task.checkCancellation()
                return value
            } catch {
                if jobs[jobKey]?.id == job.id { jobs[jobKey] = nil }
                throw error
            }
        } onCancel: { Task { await self.cancel(key: jobKey, id: job.id) } }
    }
    /// Local-only fast path: do not queue downloads, conversions or partial results.
    func cachedFiles(pack: String, sticker: RemoteSticker) async -> GalleryPreviewFiles? {
        guard maintenance == 0 else { return nil }
        let fm = FileManager.default
        let key = Self.key(pack: pack, sticker: sticker)
        let poster = root.appendingPathComponent(key + ".png")
        let gif = root.appendingPathComponent(key + ".gif")
        if fm.fileExists(atPath: poster.path) {
            let animation = sticker.format != "static" && fm.fileExists(atPath: gif.path) ? gif : nil
            for file in [poster, animation].compactMap({ $0 }) {
                try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            }
            return GalleryPreviewFiles(poster: poster, animation: animation)
        }
        if let reader = try? LibraryReader.shared(), let snapshot = try? await LibrarySnapshotLoader.shared.load(reader: reader).snapshot,
           let manifest = snapshot.packs.first(where: { $0.telegramName == pack }),
           let record = manifest.stickers.first(where: { $0.id == sticker.id }),
           record.sourceFormat == sticker.format,
           let poster = try? reader.file(record.thumbnailPath), fm.fileExists(atPath: poster.path) {
            let animation = (record.playbackPath ?? record.animationPath).flatMap { try? reader.file($0) }
            return GalleryPreviewFiles(poster: poster, animation: animation.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil })
        }
        return nil
    }
    private func make(pack: String, sticker: RemoteSticker, client: WorkerClient, key: String, animate: Bool) async throws -> GalleryPreviewFiles {
        // Reuse installed playback data before performing any preview network request.
        if let reader = try? LibraryReader.shared(), let snapshot = try? await LibrarySnapshotLoader.shared.load(reader: reader).snapshot,
           let manifest = snapshot.packs.first(where: { $0.telegramName == pack }),
           let record = manifest.stickers.first(where: { $0.id == sticker.id }),
           record.sourceFormat == sticker.format {
            let poster = try? reader.file(record.thumbnailPath)
            let animation = animate ? (record.playbackPath ?? record.animationPath).flatMap { try? reader.file($0) } : nil
            if let poster, FileManager.default.fileExists(atPath: poster.path),
               animation == nil || FileManager.default.fileExists(atPath: animation!.path) {
                return GalleryPreviewFiles(poster: poster, animation: animation)
            }
        }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let poster = root.appendingPathComponent(key + ".png")
        let gif = root.appendingPathComponent(key + ".gif")
        let animated = sticker.format != "static"
        let hadPoster = fm.fileExists(atPath: poster.path)
        if hadPoster && (!animated || !animate || fm.fileExists(atPath: gif.path)) {
            for file in [poster, gif] where fm.fileExists(atPath: file.path) { try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path) }
            return GalleryPreviewFiles(poster: poster, animation: animated && animate ? gif : nil)
        }
        try await downloads.acquire()
        defer { Task { await downloads.release() } }
        try Task.checkCancellation()
        if !hadPoster, sticker.hasThumbnail || !animated {
            do {
                let data = try await client.asset(pack: pack, sticker: sticker, thumbnail: sticker.hasThumbnail)
                let png = try Self.thumbnail(data)
                try Task.checkCancellation()
                try png.write(to: poster, options: .atomic)
            } catch is CancellationError { throw CancellationError() }
            catch { await DownloadDiagnostics.shared.record("GALLERY_POSTER pack=\(pack) stickerID=\(sticker.id) " + DownloadDiagnostics.errorDetails(error)) }
        }
        if !animated || !animate {
            return GalleryPreviewFiles(poster: fm.fileExists(atPath: poster.path) ? poster : nil, animation: nil)
        }
        let source = root.appendingPathComponent(key + ".source")
        let workingGIF = root.appendingPathComponent(key + ".working.gif")
        defer { try? fm.removeItem(at: source); try? fm.removeItem(at: workingGIF) }
        do {
            _ = try await client.assetFile(pack: pack, sticker: sticker, destination: source)
            try await conversions.acquire()
            defer { Task { await conversions.release() } }
            try Task.checkCancellation()
            guard maintenance == 0 else { throw CancellationError() }
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            let quality = AnimationQuality(pixels: 96, fps: 15)
            let converted: ConvertedAnimation
            if sticker.format == "animated" { converted = try await TGSConverter.convert(data, output: workingGIF, quality: quality) }
            else { converted = try await WebMConverter().convert(data, output: workingGIF, quality: quality) }
            try Task.checkCancellation()
            try converted.poster.write(to: poster, options: .atomic)
            if fm.fileExists(atPath: gif.path) { try fm.removeItem(at: gif) }
            try fm.moveItem(at: workingGIF, to: gif)
            trim()
            return GalleryPreviewFiles(poster: poster, animation: gif)
        } catch is CancellationError { throw CancellationError() }
        catch {
            await DownloadDiagnostics.shared.record("GALLERY_ANIMATION pack=\(pack) stickerID=\(sticker.id) " + DownloadDiagnostics.errorDetails(error))
            return GalleryPreviewFiles(poster: fm.fileExists(atPath: poster.path) ? poster : nil, animation: nil)
        }
    }
    nonisolated private static func thumbnail(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 1024, height <= 1024,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceShouldCache: false] as CFDictionary) else { throw LibraryError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw LibraryError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.invalidImage }
        return output as Data
    }
    private func trim() {
        let fm = FileManager.default
        let entries = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .compactMap { file -> (URL, Int64, Date)? in
                guard ["png", "gif", "json"].contains(file.pathExtension), let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (file, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        let keep = visible.union(jobs.keys.map { String($0.split(separator: ":")[0]) })
        for (file, size, _) in entries where total > 100 * 1024 * 1024 {
            guard !keep.contains(where: { file.lastPathComponent.hasPrefix($0) }) else { continue }
            if (try? fm.removeItem(at: file)) != nil { total -= size }
        }
    }
}
