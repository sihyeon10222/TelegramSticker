import UIKit
import Testing
@testable import TelegramSticker

@MainActor
struct KeyboardPresentationTests {
    @Test func retainedHistoryAndOrderReloadChangesFromAnotherSession() throws {
        let name = "KeyboardPresentationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let oldHistory = RecentStickerStore(defaults: defaults)
        let oldOrder = KeyboardPackOrderStore(defaults: defaults)
        let oldSelection = KeyboardSelectionStore(defaults: defaults)
        let newHistory = RecentStickerStore(defaults: defaults)
        let newOrder = KeyboardPackOrderStore(defaults: defaults)
        let newSelection = KeyboardSelectionStore(defaults: defaults)
        newHistory.record("pack.two")
        newSelection.save(.recent)
        #expect(newOrder.reorder(["b", "a"], available: ["a", "b"]))
        #expect(oldHistory.reload())
        #expect(oldHistory.ids == ["pack.two"])
        #expect(oldOrder.reload())
        #expect(oldOrder.orderedIDs(available: ["a", "b"]) == ["b", "a"])
        #expect(oldSelection.selection == .recent)
        #expect(!oldHistory.reload())
        #expect(!oldOrder.reload())
        // A copy in an older controller must preserve the newer session's history.
        newHistory.record("pack.three")
        oldHistory.record("pack.one")
        #expect(oldHistory.ids == ["pack.one", "pack.three", "pack.two"])
        newHistory.clear()
        #expect(oldHistory.reload())
        #expect(oldHistory.ids.isEmpty)
        newOrder.reset()
        #expect(oldOrder.reload())
        #expect(oldOrder.orderedIDs(available: ["a", "b"]) == ["a", "b"])
    }

    @Test func selectedPackIsImmediatelyVisibleToAnotherHostWithStalePreferences() throws {
        let nameA = "SelectionHostA." + UUID().uuidString
        let nameB = "SelectionHostB." + UUID().uuidString
        let a = try #require(UserDefaults(suiteName: nameA))
        let b = try #require(UserDefaults(suiteName: nameB))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            a.removePersistentDomain(forName: nameA); b.removePersistentDomain(forName: nameB)
            try? FileManager.default.removeItem(at: root)
        }
        a.set("all", forKey: "keyboardSelection.v1")
        b.set("recent", forKey: "keyboardSelection.v1")
        let url = root.appendingPathComponent("selection.json")
        let oldHost = KeyboardSelectionStore(defaults: a, fileURL: url)
        let newHost = KeyboardSelectionStore(defaults: b, fileURL: url)
        oldHost.save(.pack("telegram-own-pack"))
        #expect(newHost.selection == .pack("telegram-own-pack"))
        newHost.save(.recent)
        #expect(oldHost.selection == .recent)
        #expect(KeyboardSelectionStore(defaults: a, fileURL: url).selection == .recent)
        oldHost.save(.pack("../unsafe"))
        #expect(newHost.selection == .recent)
        try Data("broken".utf8).write(to: url)
        #expect(newHost.selection == .recent)
    }

    @Test func installedPacksLoadBeforeAsyncMaintenance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("own.png")
        try UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).pngData { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }.write(to: image)
        let reader = LibraryReader(root: root.appendingPathComponent("library"))
        let writer = LibraryWriter(reader: reader)
        try await writer.install(id: "own", title: "Already installed", stickers: [
            LocalStickerInput(id: "one", name: "Own image", url: image)
        ])
        let metadata = try reader.snapshot(resolvingFiles: false)
        #expect(metadata.files.isEmpty)
        let model = LibraryModel(reader: reader, writer: writer)
        await model.refresh()
        #expect(model.packs.map(\.title) == ["Already installed"])
        #expect(model.packs.first?.stickers.count == 1)
        #expect(model.cover(in: try #require(model.packs.first)) != nil)
        #expect(model.damagedPacks.isEmpty)
        // A fast catalog still rejects traversal, and asset access still checks symlinks.
        let reference = try #require(reader.index().packs.first)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: reader.file(reference.manifestPath))) as? [String: Any])
        var records = try #require(json["stickers"] as? [[String: Any]])
        records[0]["pngPath"] = "packs/own/" + (try #require(model.packs.first).revision) + "/../escape.png"
        json["stickers"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: reader.file(reference.manifestPath))
        #expect(try reader.snapshot(resolvingFiles: false).packs.isEmpty)
        #expect(try !reader.snapshot(resolvingFiles: false).warnings.isEmpty)
    }

    @Test func emptyLibraryHasStableIdentityAcrossPresentations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root)
        #expect(try reader.index().libraryRevision == reader.index().libraryRevision)
        #expect(try reader.snapshot().revision == reader.snapshot().revision)
        #expect(try reader.snapshot().packs.isEmpty)
    }

    @Test func firstPagePostersAreAllReadyBeforePresentation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96))
        let data = renderer.pngData { ctx in UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 96, height: 96)) }
        let stickers = try (0..<40).map { i -> Sticker in
            let url = root.appendingPathComponent("\(i).png")
            try data.write(to: url)
            return Sticker(id: "\(i)", name: "Own", detail: "Own", thumbnailURL: url)
        }
        let images = StickerImages(maximumPixelSize: 160)
        images.preparePosters(for: stickers, limit: 28)
        #expect(stickers.prefix(28).allSatisfy { images.cachedThumbnail(for: $0) != nil })
        #expect(stickers.dropFirst(28).allSatisfy { images.cachedThumbnail(for: $0) == nil })
    }

    @Test func cachedPosterSurvivesNewControllerAndSeparatesFileRevisions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("revision-one.png")
        let second = root.appendingPathComponent("revision-two.png")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80))
        for (url, color) in [(first, UIColor.red), (second, UIColor.blue)] {
            try renderer.pngData { ctx in color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 80)) }.write(to: url)
        }
        let old = Sticker(id: "same-id", name: "own", detail: "own", thumbnailURL: first)
        let updated = Sticker(id: "same-id", name: "own", detail: "own", thumbnailURL: second)
        let images = StickerImages(maximumPixelSize: 64)
        let poster = try #require(await images.thumbnailAsync(for: old))
        let anotherController = StickerImages(maximumPixelSize: 64)
        #expect(anotherController.cachedThumbnail(for: old) === poster)
        #expect(anotherController.cachedThumbnail(for: updated) == nil)
        let updatedPoster = try #require(await anotherController.thumbnailAsync(for: updated))
        #expect(updatedPoster.pngData() != poster.pngData())
        #expect(anotherController.cachedThumbnail(for: old) === poster)
        images.removeAll()
        #expect(anotherController.cachedThumbnail(for: old) == nil)
    }
}
