import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor @Observable
final class LibraryModel {
    @ObservationIgnored private var contents: LibraryContents?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    private static var cachedContents: LibraryContents?
    var packs: [PackManifestV1] = []
    var damagedPacks: [PackReference] = []
    var message: String?
    var isBusy = false
    var isAvailable = false
    private(set) var isLoading = true
    private(set) var reader: LibraryReader?
    private(set) var writer: LibraryWriter?

    init(reader initialReader: LibraryReader? = nil, writer initialWriter: LibraryWriter? = nil) {
        do {
            let reader = try initialReader ?? LibraryReader.shared()
            self.reader = reader
            writer = initialWriter ?? (initialReader == nil ? LibraryWriter.shared : nil)
            isAvailable = true
            if let cached = Self.cachedContents, cached.reader.root == reader.root { apply(cached) }
        } catch { message = error.localizedDescription; isLoading = false }
    }

    func refresh() async {
        guard let reader else { return }
        refreshRequested = true
        if let refreshTask { await refreshTask.value; return }
        let task = Task {
            defer { refreshTask = nil; isLoading = false }
            repeat {
                refreshRequested = false
                do {
                    let value = try await LibrarySnapshotLoader.shared.load(reader: reader)
                    // A publication during this read requires a new index check before presentation.
                    if !refreshRequested { apply(value) }
                } catch {
                    if !refreshRequested { message = error.localizedDescription }
                }
            } while refreshRequested
        }
        refreshTask = task
        await task.value
    }

    private func apply(_ value: LibraryContents) {
        let snapshot = value.snapshot
        let unchanged = contents?.snapshot.revision == snapshot.revision
            && contents?.snapshot.cacheGeneration == snapshot.cacheGeneration
            && contents?.snapshot.warnings == snapshot.warnings
            && packs.map(\.id) == snapshot.packs.map(\.id)
        contents = value
        Self.cachedContents = value
        isLoading = false
        message = snapshot.warnings.first
        guard !unchanged else { return }
        packs = snapshot.packs
        PackUpdateService.shared.reconcile(packs: packs)
        let available = Set(snapshot.packs.map(\.id))
        damagedPacks = snapshot.references.filter { !available.contains($0.id) }
    }

    func start() async {
        await refresh()
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
        contents?.stickers[pack.id] ?? []
    }

    func cover(in pack: PackManifestV1) -> Sticker? {
        contents?.covers[pack.id]
    }
}
