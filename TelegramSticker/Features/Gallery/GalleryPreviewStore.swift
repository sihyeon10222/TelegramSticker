import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Observation

nonisolated struct GalleryPreviewFiles: Sendable {
    let poster: URL?
    let animation: URL?
}

@MainActor @Observable
final class GalleryPreviewState {
    static let shared = GalleryPreviewState()
    var generation = 0
    var maintaining = false
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
        await MainActor.run { GalleryPreviewState.shared.maintaining = true }
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
    private func make(pack: String, sticker: RemoteSticker, client: WorkerClient, key: String, animate: Bool) async throws -> GalleryPreviewFiles {
        // Reuse installed playback data before performing any preview network request.
        if let reader = try? LibraryReader.shared(), let snapshot = try? reader.snapshot(resolvingFiles: false),
           let manifest = snapshot.packs.first(where: { $0.telegramName == pack }),
           let record = manifest.stickers.first(where: { $0.id == sticker.id }) {
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
                guard ["png", "gif"].contains(file.pathExtension), let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
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
