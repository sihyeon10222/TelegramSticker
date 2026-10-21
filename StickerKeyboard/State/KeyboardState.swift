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
    private static var imageCacheGeneration: String?
    private static var cachedLibrary: LibraryContents?
    private var allSections: [[Sticker]] = []
    private var allStickerCount = 0
    private var contentVersion = 0
    private var preparedVersion = -1
    private var preparedSelection: KeyboardSelection?
    private var preparedRecent: [String] = []
    private(set) var tabsRevision = 0
    private(set) var selectionRevision = 0

    private(set) var selectedSections: [[Sticker]] = []
    private(set) var stickerCount = 0
    var hasRecentStickers: Bool { !recent.ids.isEmpty }

    func shouldInvalidateImageCache(for generation: String?) -> Bool {
        let previous = Self.imageCacheGeneration
        Self.imageCacheGeneration = generation
        return previous != nil && previous != generation
    }

    private func scrollKey(for selection: KeyboardSelection) -> String {
        switch selection {
        case .all: return "keyboard.scroll.v1.all"
        case .recent: return "keyboard.scroll.v1.recent"
        case .pack(let id): return "keyboard.scroll.v1.pack." + id
        }
    }

    func saveScrollOffset(_ offset: Double) {
        guard offset.isFinite else { return }
        UserDefaults.standard.set(max(0, offset), forKey: scrollKey(for: selection))
    }

    func scrollOffset(for selection: KeyboardSelection) -> Double {
        let value = UserDefaults.standard.double(forKey: scrollKey(for: selection))
        return value.isFinite ? max(0, value) : 0
    }

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
        let restored = selectionStore.selection
        let selectionChanged = selection != restored
        selection = restored
        let historyChanged = recent.reload()
        let orderChanged = packOrder.reload()
        return selectionChanged || historyChanged || orderChanged
    }

    @discardableResult
    func restoreLibrary() -> Bool {
        guard let cached = Self.cachedLibrary,
              cached.snapshot.revision != libraryRevision || cached.snapshot.cacheGeneration != cacheGeneration else { return false }
        acceptLibrary(cached, allowPruning: false)
        return true
    }

    func acceptLibrary(_ contents: LibraryContents, allowPruning: Bool = true) {
        let snapshot = contents.snapshot
        let changed = libraryRevision != snapshot.revision || cacheGeneration != snapshot.cacheGeneration
        Self.cachedLibrary = contents
        reader = contents.reader
        libraryRevision = snapshot.revision
        cacheGeneration = snapshot.cacheGeneration
        libraryPacks = snapshot.packs
        prepared = contents.stickers
        byStickerID = contents.byStickerID
        canPruneHistory = allowPruning && snapshot.warnings.isEmpty
        if canPruneHistory { recent.prune(available: contents.stickerIDs) }
        let previousOrder = packs.map(\.id)
        restorePackOrder()
        if changed, previousOrder == packs.map(\.id) { rebuildSections() }
        libraryNote = snapshot.warnings.first
        if packs.isEmpty { libraryNote = snapshot.warnings.first ?? "설치한 스티커가 없어요. 앱에서 Telegram 팩을 추가해 주세요." }
    }

    private func rebuildSections() {
        allSections = packs.compactMap { pack in
            guard let items = prepared[pack.id], !items.isEmpty else { return nil }
            return items
        }
        allStickerCount = allSections.reduce(0) { $0 + $1.count }
        contentVersion += 1
        tabsRevision += 1
    }

    func restorePackOrder() {
        let byID = Dictionary(uniqueKeysWithValues: libraryPacks.map { ($0.id, $0) })
        let ordered = packOrder.orderedIDs(available: libraryPacks.map(\.id), prune: canPruneHistory).compactMap { byID[$0] }
        let changed = packs.map(\.id) != ordered.map(\.id)
        packs = ordered
        if changed { rebuildSections() }
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
        case .all: return allSections
        case .recent: return [recent.ids.compactMap { byStickerID[$0] }]
        case .pack(let id): return [prepared[id] ?? []]
        }
    }

    func prepareSelection() {
        let recentIDs = selection == .recent ? recent.ids : []
        guard preparedSelection != selection || preparedVersion != contentVersion || preparedRecent != recentIDs else { return }
        preparedSelection = selection
        preparedVersion = contentVersion
        preparedRecent = recentIDs
        selectedSections = sections(for: selection)
        stickerCount = selection == .all ? allStickerCount : selectedSections.reduce(0) { $0 + $1.count }
        selectionRevision += 1
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
        defer { rebuildSections() }
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
        rebuildSections()
        return true
    }
}
