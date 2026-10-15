import Foundation

/// Library and preference state. UIKit views and interaction tasks stay in the controller.
@MainActor
final class KeyboardState {
    private(set) var packs: [PackManifestV1] = []
    private(set) var prepared: [String: [Sticker]] = [:]
    private(set) var selection = KeyboardSelection.all
    private(set) var lastCopiedID: String?
    private(set) var reader: LibraryReader?
    private(set) var libraryRevision: String?
    private(set) var cacheGeneration: String?
    private(set) var libraryNote: String?
    private var libraryPacks: [PackManifestV1] = []
    private var byStickerID: [String: Sticker] = [:]
    private var canPruneHistory = false
    private let selectionStore = KeyboardSelectionStore()
    private let recent = RecentStickerStore()
    private let packOrder = KeyboardPackOrderStore()
    private static var cachedLibrary: (LibraryReader, LibrarySnapshot)?

    private(set) var stickers: [Sticker] = []
    var hasRecentStickers: Bool { !recent.ids.isEmpty }

    func restoreSelection() { selection = selectionStore.selection }

    func applyAppResetIfNeeded() {
        guard let epoch = UserDefaults(suiteName: LibraryReader.appGroup)?.string(forKey: "appResetEpoch"),
              UserDefaults.standard.string(forKey: "appliedResetEpoch") != epoch else { return }
        recent.clear()
        packOrder.reset()
        select(.all)
        UserDefaults.standard.set(epoch, forKey: "appliedResetEpoch")
    }

    @discardableResult
    func reloadPreferences() -> Bool {
        let selectionChanged = selection != selectionStore.selection
        restoreSelection()
        let historyChanged = recent.reload()
        let orderChanged = packOrder.reload()
        return selectionChanged || historyChanged || orderChanged
    }

    @discardableResult
    func restoreLibrary() -> Bool {
        do {
            let reader = try self.reader ?? LibraryReader.shared()
            let index = try reader.index()
            if index.libraryRevision == libraryRevision, canPruneHistory {
                cacheGeneration = index.cacheGeneration
                return false
            }
            let snapshot: LibrarySnapshot
            if let (_, cached) = Self.cachedLibrary, cached.revision == index.libraryRevision,
               cached.cacheGeneration == index.cacheGeneration, cached.warnings.isEmpty {
                snapshot = cached
            } else { snapshot = try reader.snapshot() }
            acceptLibrary(reader: reader, snapshot: snapshot)
            return true
        } catch {
            // A failed read does not mean installed stickers were deleted.
            canPruneHistory = false
            libraryNote = "공유 목록을 열 수 없어요. 메인 앱에서 설치된 팩을 확인해 주세요."
            return false
        }
    }

    func acceptLibrary(reader: LibraryReader, snapshot: LibrarySnapshot) {
        Self.cachedLibrary = (reader, snapshot)
        self.reader = reader
        libraryRevision = snapshot.revision
        cacheGeneration = snapshot.cacheGeneration
        libraryPacks = snapshot.packs
        prepared = Dictionary(uniqueKeysWithValues: snapshot.packs.map { pack in
            (pack.id, pack.stickers.compactMap { record -> Sticker? in
                guard let png = snapshot.files[record.pngPath], let thumb = snapshot.files[record.thumbnailPath] else { return nil }
                return Sticker(id: pack.id + "." + record.id, name: record.name, detail: pack.title, imageURL: png, thumbnailURL: thumb,
                    animationURL: record.animationPath.flatMap { snapshot.files[$0] }, playbackURL: record.playbackPath.flatMap { snapshot.files[$0] })
            })
        })
        byStickerID = Dictionary(uniqueKeysWithValues: prepared.values.flatMap { $0 }.map { ($0.id, $0) })
        canPruneHistory = snapshot.warnings.isEmpty
        restorePackOrder()
        libraryNote = snapshot.warnings.first
        if packs.isEmpty { libraryNote = snapshot.warnings.first ?? "설치한 스티커가 없어요. 앱에서 Telegram 팩을 추가해 주세요." }
    }

    func restorePackOrder() {
        let byID = Dictionary(uniqueKeysWithValues: libraryPacks.map { ($0.id, $0) })
        packs = packOrder.orderedIDs(available: libraryPacks.map(\.id), prune: canPruneHistory).compactMap { byID[$0] }
        if case .pack(let id) = selection, !packs.contains(where: { $0.id == id }), canPruneHistory { select(.all) }
    }

    func reportReloadFailure() { libraryNote = "공유 목록을 갱신하지 못했어요. 메인 앱에서 확인해 주세요." }

    func select(_ selection: KeyboardSelection, persist: Bool = true) {
        if persist { selectionStore.save(selection) }
        self.selection = selection
    }

    func persistSelection(_ selection: KeyboardSelection) { selectionStore.save(selection) }

    func sections(for selection: KeyboardSelection) -> [[Sticker]] {
        switch selection {
        case .all: return packs.compactMap { pack in
            let items = prepared[pack.id] ?? []; return items.isEmpty ? nil : items
        }
        case .recent: return [recent.ids.compactMap { byStickerID[$0] }]
        case .pack(let id): return [prepared[id] ?? []]
        }
    }

    func prepareSelection() {
        if canPruneHistory { recent.prune(available: Set(packs.flatMap { prepared[$0.id] ?? [] }.map(\.id))) }
        stickers = sections(for: selection).flatMap { $0 }
    }

    func recordCopy(_ id: String) { recent.record(id); lastCopiedID = id }
    func clearCopiedSticker() { lastCopiedID = nil }
    func clearHistory() { recent.clear(); clearCopiedSticker() }
    func resetPackOrder() { packOrder.reset() }

    func previewPackMove(from source: Int, to target: Int) {
        let pack = packs.remove(at: source)
        packs.insert(pack, at: target)
    }

    @discardableResult
    func finishPackMove(original: [PackManifestV1], commit: Bool) -> Bool {
        let changed = packs.map(\.id) != original.map(\.id)
        if commit, changed, packOrder.reorder(packs.map(\.id), available: original.map(\.id)) { return true }
        packs = original
        return false
    }

    @discardableResult
    func movePack(_ id: String, offset: Int) -> Bool {
        guard packOrder.move(id, offset: offset, available: packs.map(\.id)) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0) })
        packs = packOrder.orderedIDs(available: packs.map(\.id)).compactMap { byID[$0] }
        return true
    }
}
