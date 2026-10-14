import Foundation
import Testing
@testable import TelegramSticker

@MainActor
struct RecentStickerTests {
    @Test func boundedHistoryIsUniqueOrderedPersistentAndPrunesDeletedIDs() throws {
        let suite = "StickerBridgeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentStickerStore(defaults: defaults)
        #expect(store.ids.isEmpty)
        for i in 0..<30 { store.record("pack.sticker-\(i)") }
        #expect(store.ids.count == 24)
        #expect(store.ids.first == "pack.sticker-29")
        #expect(!store.ids.contains("pack.sticker-0"))
        store.record("pack.sticker-12")
        #expect(store.ids.first == "pack.sticker-12")
        #expect(Set(store.ids).count == 24)
        let restored = RecentStickerStore(defaults: defaults)
        #expect(restored.ids == store.ids)
        restored.prune(available: ["pack.sticker-12", "pack.sticker-29"])
        #expect(restored.ids == ["pack.sticker-12", "pack.sticker-29"])
        #expect(RecentStickerStore(defaults: defaults).ids == restored.ids)
        #expect(defaults.dictionaryRepresentation().keys.contains("recentStickerIDs.v1"))
    }

    @Test func malformedPreferencesAreBoundedAndDoNotPreventNewCopies() throws {
        let suite = "StickerBridgeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["", "valid", "valid", String(repeating: "a", count: 221)], forKey: "recentStickerIDs.v1")
        let store = RecentStickerStore(defaults: defaults)
        #expect(store.ids == ["valid"])
        store.record(""); store.record(String(repeating: "a", count: 221))
        #expect(store.ids == ["valid"])
        store.record("new")
        #expect(store.ids == ["new", "valid"])
    }
}

@MainActor
struct KeyboardPreferenceTests {
    @Test func clearedHistoryStaysEmptyAfterRestartAndCanRecordAgain() throws {
        let suite = "StickerBridgeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = RecentStickerStore(defaults: defaults)
        history.record("pack.one"); history.record("pack.two")
        history.clear()
        #expect(history.ids.isEmpty)
        #expect(RecentStickerStore(defaults: defaults).ids.isEmpty)
        history.record("pack.three")
        #expect(RecentStickerStore(defaults: defaults).ids == ["pack.three"])
    }

    @Test func keyboardOrderPersistsReconcilesDeletedAndNewPacksAndResets() throws {
        let suite = "StickerBridgeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KeyboardPackOrderStore(defaults: defaults)
        #expect(store.orderedIDs(available: ["a", "b", "c"]) == ["a", "b", "c"])
        // Until a keyboard override is made, changes in the app's ordering remain visible.
        #expect(store.orderedIDs(available: ["c", "b", "a"]) == ["c", "b", "a"])
        #expect(store.move("b", offset: -1, available: ["a", "b", "c"]))
        let restored = KeyboardPackOrderStore(defaults: defaults)
        #expect(restored.orderedIDs(available: ["a", "b", "c"]) == ["b", "a", "c"])
        #expect(restored.orderedIDs(available: ["a", "c", "new"]) == ["a", "c", "new"])
        #expect(!restored.move("a", offset: -1, available: ["a", "c", "new"]))
        #expect(!restored.move("missing", offset: 1, available: ["a", "c", "new"]))
        #expect(!restored.move("a", offset: 2, available: ["a", "c", "new"]))
        #expect(restored.move("c", offset: 1, available: ["a", "c", "new"]))
        #expect(restored.orderedIDs(available: ["a", "c", "new"]) == ["a", "new", "c"])
        restored.reset()
        #expect(KeyboardPackOrderStore(defaults: defaults).orderedIDs(available: ["c", "a", "new"]) == ["c", "a", "new"])
    }

    @Test func incompleteLibraryReadDoesNotErasePackOrdering() throws {
        let suite = "StickerBridgeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["b", "a", "b", "../unsafe", ""], forKey: "keyboardPackOrder.v1")
        let store = KeyboardPackOrderStore(defaults: defaults)
        #expect(store.orderedIDs(available: ["a"], prune: false) == ["a"])
        #expect(store.orderedIDs(available: ["a", "b"]) == ["b", "a"])
    }
}


@MainActor
struct KeyboardDragAndSelectionTests {
    @Test func dragPublishesCompletePermutationAndRejectsInvalidOrders() throws {
        let suite = "StickerBridgeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KeyboardPackOrderStore(defaults: defaults)
        let original = ["a", "b", "c", "d"]
        #expect(store.reorder(["c", "d", "a", "b"], available: original))
        #expect(KeyboardPackOrderStore(defaults: defaults).orderedIDs(available: original) == ["c", "d", "a", "b"])
        #expect(!store.reorder(["a", "b", "c"], available: original))
        #expect(!store.reorder(["a", "b", "c", "c"], available: original))
        #expect(!store.reorder(["a", "b", "c", "unknown"], available: original))
        #expect(store.orderedIDs(available: original) == ["c", "d", "a", "b"])
    }

    @Test func selectedListSurvivesFreshStoreAndRejectsMalformedValues() throws {
        let suite = "StickerBridgeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KeyboardSelectionStore(defaults: defaults)
        #expect(store.selection == .all)
        store.save(.recent)
        #expect(KeyboardSelectionStore(defaults: defaults).selection == .recent)
        store.save(.pack("telegram-test_pack"))
        #expect(KeyboardSelectionStore(defaults: defaults).selection == .pack("telegram-test_pack"))
        store.save(.pack("../unsafe"))
        #expect(store.selection == .pack("telegram-test_pack"))
        defaults.set("pack:../unsafe", forKey: "keyboardSelection.v1")
        #expect(store.selection == .all)
        defaults.set("unknown", forKey: "keyboardSelection.v1")
        #expect(store.selection == .all)
        store.save(.all)
        #expect(KeyboardSelectionStore(defaults: defaults).selection == .all)
    }
}
