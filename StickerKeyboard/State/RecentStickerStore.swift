import Foundation

/// Uses this process's own defaults, never the shared App Group suite.
/// Stores only explicitly copied sticker IDs, no text context or clipboard contents.
@MainActor
final class RecentStickerStore {
    private let defaults: UserDefaults
    private let key = "recentStickerIDs.v1"
    private(set) var ids: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = []
        reload()
    }

    /// A retained controller must not keep history from another keyboard session.
    @discardableResult
    func reload() -> Bool {
        var seen = Set<String>()
        let loaded = (defaults.stringArray(forKey: key) ?? []).filter {
            !$0.isEmpty && $0.utf8.count <= 220 && seen.insert($0).inserted
        }
        guard loaded != ids else { return false }
        ids = loaded
        return true
    }

    func record(_ id: String) {
        guard !id.isEmpty, id.utf8.count <= 220 else { return }
        reload()
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        defaults.set(ids, forKey: key)
    }

    func clear() {
        ids = []
        defaults.removeObject(forKey: key)
    }

    func prune(available: Set<String>) {
        let retained = ids.filter { available.contains($0) }
        guard retained != ids else { return }
        ids = retained
        defaults.set(ids, forKey: key)
    }
}
