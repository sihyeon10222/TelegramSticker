import Foundation
import Testing
@testable import TelegramSticker

@MainActor
struct LibraryTests {
    private func fixture() throws -> (LibraryReader, [LocalStickerInput]) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let inputs = try SampleSticker.all.map {
            LocalStickerInput(id: $0.id, name: $0.name, url: try #require($0.fileURL()))
        }
        return (LibraryReader(root: root), inputs)
    }

    @Test func installPublishesWholePackAndRestartReadsSameRevision() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader, publish: { data, url in
            // Files have moved into place, but the reader must still see an empty library.
            #expect(try reader.snapshot().packs.isEmpty)
            try data.write(to: url, options: .atomic)
        })
        try await writer.install(id: "first", title: "첫 팩", stickers: inputs)
        let result = try reader.snapshot()
        #expect(result.packs.count == 1)
        #expect(result.packs[0].stickers.count == 3)
        for (record, input) in zip(result.packs[0].stickers, inputs) {
            #expect(try Data(contentsOf: reader.file(record.pngPath)) == Data(contentsOf: input.url))
            #expect(try PNGValidation.isValid(Data(contentsOf: reader.file(record.thumbnailPath))))
            #expect(record.sha256.count == 64)
        }
        let restarted = LibraryReader(root: reader.root)
        #expect(try restarted.snapshot().revision == result.revision)
    }

    @Test func failedPublicationAndInvalidPNGPreserveExistingLibrary() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        try await writer.install(id: "first", title: "첫 팩", stickers: inputs)
        let before = try Data(contentsOf: reader.file("index.json"))
        let failing = LibraryWriter(reader: reader, publish: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await #expect(throws: CocoaError.self) { try await failing.install(id: "second", title: "실패", stickers: inputs) }
        let invalid = reader.root.appendingPathComponent("broken.png")
        try Data("broken".utf8).write(to: invalid)
        await #expect(throws: LibraryError.self) {
            try await writer.install(id: "broken", title: "손상", stickers: [.init(id: "bad", name: "손상", url: invalid)])
        }
        #expect(try Data(contentsOf: reader.file("index.json")) == before)
        #expect(try reader.snapshot().packs.map(\.id) == ["first"])
    }

    @Test func duplicateConcurrentInstallCannotCreateTwoPacks() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        async let first: Void? = try? writer.install(id: "same", title: "하나", stickers: inputs)
        async let second: Void? = try? writer.install(id: "same", title: "하나", stickers: inputs)
        _ = await (first, second)
        #expect(try reader.snapshot().packs.count == 1)
    }

    @Test func retryPublicationPreservesOldRevisionOnFailureAndPackPositionOnSuccess() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        let id = "telegram-testpack"
        try await writer.install(id: id, title: "일부 설치", stickers: Array(inputs.prefix(1)), originalCount: 3,
            telegramName: "testpack", pendingStickerIDs: Array(inputs.dropFirst().map(\.id)))
        try await writer.install(id: "other", title: "다른 팩", stickers: inputs)
        try await writer.reorder(ids: ["other", id])
        let previous = try #require(reader.snapshot().packs.first { $0.id == id })
        let index = try Data(contentsOf: reader.file("index.json"))
        let failing = LibraryWriter(reader: reader, publish: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await #expect(throws: CocoaError.self) {
            try await failing.install(id: id, title: "완료", stickers: inputs, originalCount: 3,
                telegramName: "testpack", pendingStickerIDs: [], replacingRevision: previous.revision)
        }
        #expect(try Data(contentsOf: reader.file("index.json")) == index)
        #expect(try reader.snapshot().packs.last?.pendingStickerIDs?.count == 2)
        await #expect(throws: LibraryError.self) {
            try await writer.install(id: id, title: "잘못된 변경", stickers: inputs, originalCount: 3,
                telegramName: "testpack", pendingStickerIDs: [], replacingRevision: "stale")
        }
        try await writer.install(id: id, title: "완료", stickers: inputs, originalCount: 3,
            telegramName: "testpack", pendingStickerIDs: [], replacingRevision: previous.revision)
        #expect(try reader.snapshot().packs.map(\.id) == ["other", id])
        #expect(try reader.snapshot().packs.last?.stickers.count == 3)
        #expect(try reader.snapshot().packs.last?.pendingStickerIDs == [])
        #expect(FileManager.default.fileExists(atPath: try reader.file(previous.stickers[0].pngPath).path))
        try await writer.delete(id: id)
        await #expect(throws: LibraryError.self) {
            try await writer.install(id: id, title: "삭제 후 재시도", stickers: inputs, originalCount: 3,
                telegramName: "testpack", pendingStickerIDs: [], replacingRevision: previous.revision)
        }
        #expect(try reader.snapshot().packs.map(\.id) == ["other"])
    }

    @Test func reorderDeleteAndStaleOrder() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        for id in ["one", "two"] { try await writer.install(id: id, title: id, stickers: inputs) }
        try await writer.reorder(ids: ["two", "one"])
        #expect(try reader.snapshot().packs.map(\.id) == ["two", "one"])
        let oldPath = try #require(reader.snapshot().packs.first?.stickers.first?.pngPath)
        try await writer.delete(id: "two")
        #expect(!FileManager.default.fileExists(atPath: try reader.file(oldPath).path))
        #expect(try reader.snapshot().packs.map(\.id) == ["one"])
        await #expect(throws: LibraryError.self) { try await writer.reorder(ids: ["two", "one"]) }
        try await writer.delete(id: "one")
        #expect(try reader.snapshot().packs.isEmpty)
    }

    @Test func malformedIndexAndNewSchemaDoNotEraseFiles() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        try await writer.install(id: "one", title: "하나", stickers: inputs)
        let image = try reader.file(#require(reader.snapshot().packs.first?.stickers.first?.pngPath))
        let validIndex = try reader.index()
        try Data("invalid json".utf8).write(to: reader.file("index.json"))
        #expect(throws: LibraryError.self) { try reader.snapshot() }
        await #expect(throws: LibraryError.self) { try await writer.recover() }
        #expect(FileManager.default.fileExists(atPath: image.path))
        var future = validIndex
        future.schemaVersion = 999
        try JSONEncoder().encode(future).write(to: reader.file("index.json"))
        #expect(throws: LibraryError.self) { try reader.snapshot() }
        await #expect(throws: LibraryError.self) { try await writer.delete(id: "one") }
        #expect(FileManager.default.fileExists(atPath: image.path))
    }

    @Test func unsafePathsAndSymlinksAreRejected() throws {
        let (reader, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        for path in ["../escape", "/absolute", "packs//image", "packs/./image", "packs/../../escape", "packs/evil\\name", "packs/null\0name"] {
            #expect(throws: LibraryError.self) { try reader.file(path) }
        }
        try FileManager.default.createSymbolicLink(at: reader.root.appendingPathComponent("linked"),
                                                  withDestinationURL: reader.root.deletingLastPathComponent())
        #expect(throws: LibraryError.self) { try reader.file("linked/image.png") }
    }

    @Test func snapshotStillRejectsSymlinkLeavesAfterCheckingSharedParents() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        try await writer.install(id: "one", title: "하나", stickers: inputs)
        try await writer.install(id: "two", title: "둘", stickers: inputs)
        let snapshot = try reader.snapshot()
        let path = try #require(snapshot.packs.first?.stickers.last?.pngPath)
        let leaf = try reader.file(path)
        try FileManager.default.removeItem(at: leaf)
        try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: inputs[0].url)
        let loaded = try reader.snapshot()
        #expect(loaded.packs.map(\.id) == ["two"])
        #expect(loaded.warnings.count == 1)
    }

    @Test func missingManifestIsIsolatedAndMissingPNGDoesNotCrashReader() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        for id in ["one", "two"] { try await writer.install(id: id, title: id, stickers: inputs) }
        let index = try reader.index()
        try FileManager.default.removeItem(at: reader.file(index.packs[0].manifestPath))
        let snapshot = try reader.snapshot()
        #expect(snapshot.packs.map(\.id) == ["two"])
        #expect(snapshot.warnings.count == 1)
        let path = try #require(snapshot.packs.first?.stickers.first?.pngPath)
        try FileManager.default.removeItem(at: reader.file(path))
        #expect(try reader.snapshot().packs.count == 1)
        #expect(StickerCopyService().copyPNG(at: try reader.file(path), isAllowed: true) == .fileUnavailable)
    }

    @Test func interruptedStagingAndOldOrphansAreCollectedWithoutDeletingPublishedPack() async throws {
        let (reader, inputs) = try fixture()
        defer { try? FileManager.default.removeItem(at: reader.root) }
        let writer = LibraryWriter(reader: reader)
        try await writer.install(id: "one", title: "하나", stickers: inputs)
        let stage = try reader.file("staging/interrupted")
        let orphan = try reader.file("packs/one/orphan")
        for url in [stage, orphan] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try await writer.recover(now: Date().addingTimeInterval(90_000))
        #expect(!FileManager.default.fileExists(atPath: stage.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        let published = try #require(reader.snapshot().packs.first?.stickers.first?.pngPath)
        #expect(FileManager.default.fileExists(atPath: try reader.file(published).path))
    }
}
