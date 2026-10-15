import Foundation
#if KEYBOARD_TEST_SUPPORT
@testable import TelegramSticker
#endif

/// Keyboard-only preferences. Shared pack files remain read-only in the extension.
@MainActor
final class KeyboardPackOrderStore {
    private let defaults: UserDefaults
    private let key = "keyboardPackOrder.v1"
    private var ids: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = []
        reload()
    }

    @discardableResult
    func reload() -> Bool {
        var seen = Set<String>()
        let loaded = Array((defaults.stringArray(forKey: key) ?? []).filter {
            LibraryReader.safeID($0) && seen.insert($0).inserted
        }.prefix(1_000))
        guard loaded != ids else { return false }
        ids = loaded
        return true
    }

    func orderedIDs(available: [String], prune: Bool = true) -> [String] {
        let availableSet = Set(available)
        let retained = ids.filter { availableSet.contains($0) }
        if prune, !ids.isEmpty, retained != ids {
            ids = retained
            defaults.set(ids, forKey: key)
        }
        let retainedSet = Set(retained)
        return retained + available.filter { !retainedSet.contains($0) }
    }

    @discardableResult
    func move(_ id: String, offset: Int, available: [String]) -> Bool {
        reload()
        var order = orderedIDs(available: available)
        guard let position = order.firstIndex(of: id), (-1...1).contains(offset), offset != 0,
              order.indices.contains(position + offset) else { return false }
        order.swapAt(position, position + offset)
        ids = order
        defaults.set(ids, forKey: key)
        return true
    }

    /// A drag publishes one complete permutation, rather than writing every intermediate hover.
    @discardableResult
    func reorder(_ order: [String], available: [String]) -> Bool {
        guard order.count == available.count, Set(order).count == order.count,
              Set(order) == Set(available), order.allSatisfy(LibraryReader.safeID) else { return false }
        ids = order
        defaults.set(ids, forKey: key)
        return true
    }

    func reset() {
        ids = []
        defaults.removeObject(forKey: key)
    }
}
