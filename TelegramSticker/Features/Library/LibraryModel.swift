import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor @Observable
final class LibraryModel {
    @ObservationIgnored private var stickerCache: [String: [Sticker]] = [:]
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var coverCache: [String: Sticker] = [:]
    var packs: [PackManifestV1] = []
    var damagedPacks: [PackReference] = []
    var message: String?
    var isBusy = false
    var isAvailable = false
    private(set) var reader: LibraryReader?
    private(set) var writer: LibraryWriter?

    init(reader initialReader: LibraryReader? = nil, writer initialWriter: LibraryWriter? = nil) {
        do {
            let reader = try initialReader ?? LibraryReader.shared()
            self.reader = reader
            writer = initialWriter ?? (initialReader == nil ? LibraryWriter.shared : nil)
            isAvailable = true
            // Published manifests are ready to display; maintenance must not gate the first frame.
            let snapshot = try reader.snapshot(resolvingFiles: false)
            packs = snapshot.packs
            PackUpdateService.shared.reconcile(packs: packs)
            let available = Set(snapshot.packs.map(\.id))
            damagedPacks = try reader.index().packs.filter { !available.contains($0.id) }
            message = snapshot.warnings.first
        } catch { message = error.localizedDescription }
    }

    func refresh() async {
        guard let reader else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            let (snapshot, references) = try await Task.detached { (try reader.snapshot(resolvingFiles: false), try reader.index().packs) }.value
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            packs = snapshot.packs
            PackUpdateService.shared.reconcile(packs: packs)
            let revisions = Set(packs.map { $0.id + "." + $0.revision })
            stickerCache = stickerCache.filter { revisions.contains($0.key) }
            coverCache = coverCache.filter { revisions.contains($0.key) }
            damagedPacks = references.filter { reference in !snapshot.packs.contains { $0.id == reference.id } }
            message = snapshot.warnings.first
        } catch {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            message = error.localizedDescription
        }
    }

    func start() async {
        if let writer {
            do { try await writer.recover() } catch { message = error.localizedDescription }
        }
        await refresh()
        await PackUpdateService.shared.restore(packs: packs)
        if let writer {
            do { try await writer.preparePlaybackFiles(); await refresh() } catch { message = error.localizedDescription }
        }
    }

    func delete(ids: [String]) async {
        guard let writer, !isBusy, !ids.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            for id in ids { try await writer.delete(id: id) }
            await refresh()
        } catch { message = error.localizedDescription; await reloadPreservingMessage() }
    }

    func move(from: IndexSet, to: Int) async {
        guard let writer, !isBusy else { return }
        var reordered = packs
        reordered.move(fromOffsets: from, toOffset: to)
        packs = reordered
        isBusy = true
        defer { isBusy = false }
        do {
            try await writer.reorder(ids: reordered.map(\.id))
            await refresh()
        } catch { message = error.localizedDescription; await reloadPreservingMessage() }
    }

    private func reloadPreservingMessage() async {
        let previous = message
        await refresh()
        message = previous
    }

    func stickers(in pack: PackManifestV1) -> [Sticker] {
        let key = pack.id + "." + pack.revision
        if let cached = stickerCache[key] { return cached }
        guard let reader else { return [] }
        let result: [Sticker] = pack.stickers.compactMap { record in
            guard let png = try? reader.file(record.pngPath),
                  let thumbnail = try? reader.file(record.thumbnailPath) else { return nil }
            return Sticker(id: "\(pack.id).\(record.id)", name: record.name, detail: pack.title,
                                 imageURL: png, thumbnailURL: thumbnail,
                                 animationURL: record.animationPath.flatMap { try? reader.file($0) })
        }
        stickerCache[key] = result
        return result
    }

    func cover(in pack: PackManifestV1) -> Sticker? {
        let key = pack.id + "." + pack.revision
        if let cached = coverCache[key] { return cached }
        guard let reader, let record = pack.stickers.first,
              let url = try? reader.file(record.thumbnailPath) else { return nil }
        let cover = Sticker(id: key, name: pack.title, detail: "", thumbnailURL: url,
                            animationURL: (record.playbackPath ?? record.animationPath).flatMap { try? reader.file($0) })
        coverCache[key] = cover
        return cover
    }
}
