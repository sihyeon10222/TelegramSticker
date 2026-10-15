import Foundation
import ImageIO
import Testing
import UIKit
@testable import TelegramSticker

nonisolated final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: ((URLRequest) throws -> (Int, Data, [String: String]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data, headers) = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor
struct ImportTests {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let url = bundle.url(forResource: name, withExtension: "webp") ?? bundle.url(forResource: name, withExtension: "webp", subdirectory: "Fixtures")
        return try Data(contentsOf: #require(url))
    }
    private func client() throws -> WorkerClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        return WorkerClient(configuration: try WorkerConfiguration(address: "https://fixture.example", accessKey: "private-test-key-long-enough"),
                            session: URLSession(configuration: config))
    }
    private func pack() -> RemotePack {
        RemotePack(name: "testpack", title: "테스트 팩", stickerType: "regular", stickers: [
            RemoteSticker(id: String(repeating: "a", count: 64), format: "static", width: 512, height: 512, emoji: "🙂", fileSize: nil, hasThumbnail: true),
            RemoteSticker(id: String(repeating: "b", count: 64), format: "static", width: 512, height: 512, emoji: nil, fileSize: nil, hasThumbnail: true)
        ])
    }

    @Test func batchContinuesAfterInvalidLinkAndMissingPackAndSkipsDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library"))
        let model = ImportModel(writer: LibraryWriter(reader: reader), root: root.appendingPathComponent("jobs"))
        model.client = try client()
        let data = try fixture("alpha-lossless")
        FixtureURLProtocol.respond = { request in
            let path = request.url!.path
            if path.contains("/missing") { return (404, Data(#"{"error":{"code":"pack_not_found","retryable":false}}"#.utf8), [:]) }
            if path.contains("/assets/") { return (200, data, [:]) }
            return (200, try JSONEncoder().encode(RemotePack(name: "testpack", title: "테스트", stickerType: "regular", stickers: [
                RemoteSticker(id: String(repeating: "a", count: 64), format: "static", width: 512, height: 512, emoji: nil, fileSize: nil, hasThumbnail: false)
            ])), [:])
        }
        model.link = "잘못된 링크"
        model.additionalLinks = ["https://t.me/addstickers/missing", "https://t.me/addstickers/testpack", "https://t.me/addstickers/TESTPACK"].map {
            var item = AdditionalPackLink(); item.value = $0; return item
        }
        model.downloadBatch()
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while model.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.busy)
        #expect(try reader.snapshot().packs.map(\.id) == ["telegram-testpack"])
        #expect(model.batchStatuses[0].status.hasPrefix("실패"))
        #expect(model.batchStatuses[1].status.hasPrefix("실패"))
        #expect(model.batchStatuses[2].status == "1개 설치 완료")
        #expect(model.batchStatuses[3].status.hasPrefix("중복"))
        model.downloadBatch()
        while model.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.batchStatuses[2].status.hasPrefix("이미 설치됨"))
    }

    @Test func linkParserAcceptsOnlyExplicitPublicStickerLinks() throws {
        #expect(try StickerLink.parse("  https://t.me/addstickers/My_Pack/ \n") == "my_pack")
        #expect(try StickerLink.parse("https://telegram.me/addstickers/A1") == "a1")
        for link in ["http://t.me/addstickers/a", "https://t.me.evil.test/addstickers/a", "https://t.me:443/addstickers/a",
                     "https://me@t.me/addstickers/a", "https://t.me/addstickers/a?x=1", "https://t.me/addstickers/a#x",
                     "https://t.me/addstickers/%61", "https://t.me/addstickers/a//", "https://t.me/addstickers/../a",
                     "https://t.me/addstickers/" + String(repeating: "a", count: 65), "tg://addstickers?set=a"] {
            #expect(throws: StickerImportError.self) { try StickerLink.parse(link) }
        }
    }

    @Test func serverConfigurationRejectsCredentialURLsAndBotTokens() {
        for address in ["http://fixture.example", "https://a:b@fixture.example", "https://fixture.example/path", "https://fixture.example?token=1"] {
            #expect(throws: StickerImportError.self) { try WorkerConfiguration(address: address, accessKey: "private-test-key-long-enough") }
        }
        #expect(throws: StickerImportError.self) { try WorkerConfiguration(address: "https://fixture.example", accessKey: "123456:THIS_IS_NOT_AN_ACCESS_KEY") }
    }

    @Test func imageIOConvertsLossyAndLosslessWebPWithAlphaAndRejectsAnimation() async throws {
        let converter = StaticImageConverter()
        for name in ["alpha-lossless", "alpha-lossy"] {
            let png = try await converter.png(from: fixture(name))
            #expect(PNGValidation.isValid(png))
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 512 && image.height == 512)
            let context = try #require(CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))
            let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            let alpha = stride(from: 3, to: 512 * 512 * 4, by: 4).map { bytes[$0] }
            #expect(alpha.contains(0)); #expect(alpha.contains(255)); #expect(alpha.contains { $0 > 0 && $0 < 255 })
        }
        await #expect(throws: StickerImportError.self) { try await converter.png(from: fixture("animated")) }
        await #expect(throws: StickerImportError.self) { try await converter.png(from: Data("broken".utf8)) }
        await #expect(throws: StickerImportError.self) { try await converter.png(from: Data(repeating: 0, count: 2 * 1024 * 1024 + 1)) }
    }

    @Test func clientValidatesMetadataAndDoesNotRetryUnauthorized() async throws {
        let body = try JSONEncoder().encode(pack())
        var requests = 0
        FixtureURLProtocol.respond = { request in
            requests += 1
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-test-key-long-enough")
            return (200, body, [:])
        }
        let client = try client()
        #expect(try await client.pack(name: "testpack") == pack())
        await #expect(throws: StickerImportError.self) { try await client.pack(name: "different") }
        requests = 0
        FixtureURLProtocol.respond = { _ in
            requests += 1
            return (401, Data(#"{"error":{"code":"unauthorized","retryable":false}}"#.utf8), [:])
        }
        await #expect(throws: StickerImportError.self) { try await client.pack(name: "testpack") }
        #expect(requests == 1)
    }

    @Test func partialImportIsUsableAndRetryAfterRestartFetchesOnlyMissingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library"))
        let writer = LibraryWriter(reader: reader)
        let coordinator = ImportCoordinator(writer: writer, root: root.appendingPathComponent("jobs"))
        let webp = try fixture("alpha-lossless")
        let pack = pack(), client = try client()
        let firstID = pack.stickers[0].id, secondID = pack.stickers[1].id
        let lock = NSLock()
        var requests: [String: Int] = [:]
        var allowSecond = false
        FixtureURLProtocol.respond = { request in
            lock.lock(); defer { lock.unlock() }
            let id = request.url!.lastPathComponent
            requests[id, default: 0] += 1
            #expect(id == firstID || id == secondID)
            return (200, id == secondID && !allowSecond ? Data("bad file".utf8) : webp, [:])
        }
        let partial = try await coordinator.install(pack, client: client) { _ in }
        #expect(partial.installed == 1 && partial.failed == 1 && partial.total == 2)
        let first = try #require(reader.snapshot().packs.first)
        #expect(first.stickers.map(\.id) == [firstID])
        #expect(first.pendingStickerIDs == [secondID])
        #expect(first.telegramName == "testpack")
        let oldPNG = try reader.file(first.stickers[0].pngPath)
        #expect(PNGValidation.isValid(try Data(contentsOf: oldPNG)))
        let changedRemote = RemotePack(name: pack.name, title: pack.title, stickerType: pack.stickerType,
            stickers: [pack.stickers[0]])
        let unavailable = try await coordinator.install(changedRemote, client: client) { _ in }
        #expect(unavailable.installed == 1 && unavailable.failed == 1 && unavailable.total == 2)
        #expect(requests[firstID] == 1 && requests[secondID] == 1)
        // A different import may reclaim all job files. Installed files still supply retry inputs.
        try FileManager.default.removeItem(at: root.appendingPathComponent("jobs"))
        let restarted = ImportCoordinator(writer: LibraryWriter(reader: LibraryReader(root: reader.root)), root: root.appendingPathComponent("jobs"))
        let unchanged = try await restarted.install(pack, client: client) { _ in }
        #expect(unchanged.installed == 1 && unchanged.failed == 1)
        #expect(try reader.snapshot().packs.first?.revision == first.revision)
        allowSecond = true
        let complete = try await restarted.install(pack, client: client) { _ in }
        #expect(complete.installed == 2 && complete.failed == 0)
        let installed = try #require(reader.snapshot().packs.first)
        #expect(installed.stickers.count == 2)
        #expect(installed.originalCount == 2)
        #expect(requests[firstID] == 1 && requests[secondID] == 3)
        #expect(installed.pendingStickerIDs == [])
        #expect(installed.stickers.map(\.id) == [firstID, secondID])
        #expect(FileManager.default.fileExists(atPath: oldPNG.path)) // Old keyboard snapshot remains readable.
        #expect(installed.stickers.allSatisfy { $0.sourceFormat == "static" })
        await #expect(throws: LibraryError.self) { try await coordinator.install(pack, client: client) { _ in } }
        #expect(requests[firstID] == 1 && requests[secondID] == 3) // Duplicate import makes no network requests.
        #expect(try reader.snapshot().packs.count == 1)
    }

    @Test func allFailedImportDoesNotPublishAnEmptyPack() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library"))
        let coordinator = ImportCoordinator(writer: LibraryWriter(reader: reader), root: root.appendingPathComponent("jobs"))
        FixtureURLProtocol.respond = { _ in (200, Data("bad".utf8), [:]) }
        await #expect(throws: StickerImportError.self) { try await coordinator.install(pack(), client: client()) { _ in } }
        #expect(try reader.snapshot().packs.isEmpty)
    }

    @Test func draftRestorationIsScopedToServerAndValidated() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = ImportCoordinator(writer: LibraryWriter(reader: LibraryReader(root: root.appendingPathComponent("library"))), root: root)
        let origin = URL(string: "https://fixture.example")!
        let draft = ImportDraft(origin: origin, link: "https://t.me/addstickers/testpack", pack: pack())
        try await coordinator.saveDraft(draft)
        #expect(try await coordinator.draft(for: origin)?.pack == pack())
        #expect(try await coordinator.draft(for: URL(string: "https://other.example")!) == nil)
    }

    @Test func animatedImportPublishesGIFAndPosterAndRetryReusesBothFiles() async throws {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        func animation(_ ext: String) throws -> Data {
            try Data(contentsOf: #require(bundle.url(forResource: "moving-circle", withExtension: ext)
                ?? bundle.url(forResource: "moving-circle", withExtension: ext, subdirectory: "Fixtures")))
        }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library"))
        let coordinator = ImportCoordinator(writer: LibraryWriter(reader: reader), root: root.appendingPathComponent("jobs"))
        let tgs = try animation("tgs"), webm = try animation("webm")
        let ids = [String(repeating: "d", count: 64), String(repeating: "e", count: 64)]
        let pack = RemotePack(name: "animations", title: "움직이는 자체 테스트", stickerType: "regular", stickers: [
            RemoteSticker(id: ids[0], format: "animated", width: 512, height: 512, emoji: nil, fileSize: tgs.count, hasThumbnail: false),
            RemoteSticker(id: ids[1], format: "video", width: 512, height: 512, emoji: nil, fileSize: webm.count, hasThumbnail: false)
        ])
        var retry = false, calls: [String: Int] = [:]
        FixtureURLProtocol.respond = { request in
            let id = request.url!.lastPathComponent
            calls[id, default: 0] += 1
            return (200, id == ids[0] ? tgs : retry ? webm : Data("broken".utf8), [:])
        }
        let partial = try await coordinator.install(pack, client: client()) { _ in }
        #expect(partial.installed == 1 && partial.failed == 1)
        let first = try #require(reader.snapshot().packs.first)
        #expect(first.stickers.count == 1 && first.stickers[0].animationPath != nil)
        retry = true
        try await coordinator.install(pack, client: client()) { _ in }
        #expect(calls[ids[0]] == 1 && calls[ids[1]] == 2)
        let installed = try #require(reader.snapshot().packs.first)
        #expect(installed.stickers.map(\.sourceFormat) == ["animated", "video"])
        for record in installed.stickers {
            let gif = try Data(contentsOf: reader.file(#require(record.animationPath)))
            let png = try Data(contentsOf: reader.file(record.pngPath))
            #expect(GIFValidation.isValid(gif)); #expect(PNGValidation.isValid(png))
            var writtenGIF: Data?, writtenPNG: Data?, reads = 0
            let service = StickerCopyService(loadData: { url in reads += 1; return try Data(contentsOf: url) },
                writePNG: { writtenPNG = $0 }, writeGIF: { writtenGIF = $0 })
            let sticker = Sticker(id: record.id, name: record.name, detail: installed.title,
                imageURL: try reader.file(record.pngPath), animationURL: try reader.file(#require(record.animationPath)))
            #expect(service.copy(sticker, isAllowed: false) == .fullAccessRequired)
            #expect(reads == 0 && writtenGIF == nil && writtenPNG == nil)
            #expect(service.copy(sticker, isAllowed: true) == .copied && writtenGIF == gif)
            #expect(service.copy(sticker, isAllowed: true, asPNG: true) == .copied && writtenPNG == png)
            let bad = StickerCopyService(loadData: { _ in Data("invalid".utf8) }, writeGIF: { _ in Issue.record("invalid GIF written") })
            #expect(bad.copy(sticker, isAllowed: true) == .invalidPNG)
        }
    }

    @Test func jobCacheRetainsRetryButReclaimsOtherJobsAndProtectsActiveImport() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ImportJobCache()
        let first = String(repeating: "a", count: 64), second = String(repeating: "b", count: 64)
        let directory = try await cache.begin(root: root, key: first)
        let png = directory.appendingPathComponent("prepared.png")
        try Data("prepared".utf8).write(to: png)
        await #expect(throws: StickerImportError.self) { try await cache.begin(root: root, key: second) }
        #expect(FileManager.default.fileExists(atPath: png.path))
        await cache.end(root: root)
        _ = try await cache.begin(root: root, key: first)
        #expect(FileManager.default.fileExists(atPath: png.path))
        await cache.end(root: root)
        let unknown = root.appendingPathComponent("notes.txt")
        try Data("untouched".utf8).write(to: unknown)
        _ = try await cache.begin(root: root, key: second)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(FileManager.default.fileExists(atPath: unknown.path))
        await cache.end(root: root)
    }

    @Test func cancellationDoesNotPublishAndCanResumeWithoutStaleLease() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library"))
        let writer = LibraryWriter(reader: reader)
        let webp = try fixture("alpha-lossless")
        let original = root.appendingPathComponent("existing.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await StaticImageConverter().png(from: webp).write(to: original)
        try await writer.install(id: "existing", title: "기존 팩", stickers: [LocalStickerInput(id: "one", name: "하트", url: original)])
        let previous = try reader.index().libraryRevision
        let coordinator = ImportCoordinator(writer: writer, root: root.appendingPathComponent("jobs"))
        let client = try client(), pack = pack()
        FixtureURLProtocol.respond = { _ in (200, webp, [:]) }
        let operation = Task {
            try await coordinator.install(pack, client: client) { progress in
                if progress.completed > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try reader.index().libraryRevision == previous)
        #expect(try reader.snapshot().packs.map(\.id) == ["existing"])
        try await coordinator.install(pack, client: client) { _ in }
        #expect(try reader.snapshot().packs.map(\.id) == ["existing", "telegram-testpack"])
    }
    @Test func freshUpdateMirrorsOrderAndDeletionAndPreservesOldPackOnFailure() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library"))
        let writer = LibraryWriter(reader: reader)
        let coordinator = ImportCoordinator(writer: writer, root: root.appendingPathComponent("jobs"))
        let client = try client(), original = pack(), webp = try fixture("alpha-lossless")
        var requests = 0
        FixtureURLProtocol.respond = { _ in requests += 1; return (200, webp, [:]) }
        try await coordinator.install(original, client: client) { _ in }
        let before = try #require(reader.snapshot().packs.first)
        let new = RemoteSticker(id: String(repeating: "c", count: 64), format: "static", width: 512, height: 512, emoji: nil, fileSize: nil, hasThumbnail: false)
        let update = RemotePack(name: original.name, title: "업데이트", stickerType: "regular",
            stickers: [original.stickers[1], new], fetchedAt: Date().timeIntervalSince1970, refreshed: true)
        FixtureURLProtocol.respond = { _ in requests += 1; return (200, Data("damaged".utf8), [:]) }
        await #expect(throws: StickerImportError.self) { try await coordinator.install(update, client: client, updating: true) { _ in } }
        #expect(try reader.snapshot().packs.first?.revision == before.revision)
        let failures = await ImportFailureStore.shared.load(name: original.name)
        #expect(failures.count == 1 && failures.first?.stage == "변환")
        FixtureURLProtocol.respond = { _ in requests += 1; return (200, webp, [:]) }
        let result = try await coordinator.install(update, client: client, updating: true) { _ in }
        #expect(result.installed == 2 && result.failed == 0)
        let updated = try #require(reader.snapshot().packs.first)
        #expect(updated.stickers.map(\.id) == [original.stickers[1].id, new.id])
        #expect(updated.lastCheckedAt != nil)
        #expect(requests == 4) // Two initial files, one failed new file, one retry; unchanged item reused.
        try FileManager.default.removeItem(at: reader.file(updated.stickers[0].pngPath))
        try await coordinator.install(update, client: client, updating: true) { _ in }
        #expect(requests == 5) // Repair only the missing local original.
        #expect(PNGValidation.isValid(try Data(contentsOf: reader.file(#require(reader.snapshot().packs.first?.stickers.first?.pngPath)))))
        let empty = RemotePack(name: original.name, title: original.title, stickerType: "regular", stickers: [], fetchedAt: Date().timeIntervalSince1970, refreshed: true)
        try await coordinator.install(empty, client: client, updating: true) { _ in }
        #expect(try reader.snapshot().packs.first?.stickers.isEmpty == true)
        #expect(requests == 5)
    }

    @Test func cancelledOrDeletedUpdateCannotResurrectPackAndLegacyServerCannotClaimFreshness() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library")), original = pack()
        let writer = LibraryWriter(reader: reader), webp = try fixture("alpha-lossless"), client = try client()
        let coordinator = ImportCoordinator(writer: writer, root: root.appendingPathComponent("jobs"))
        FixtureURLProtocol.respond = { _ in (200, webp, [:]) }
        try await coordinator.install(original, client: client) { _ in }
        FixtureURLProtocol.respond = { _ in (200, try JSONEncoder().encode(original), [:]) }
        await #expect(throws: StickerImportError.self) { try await client.pack(name: original.name, refresh: true) }
        let fresh = RemotePack(name: original.name, title: original.title, stickerType: "regular", stickers: original.stickers,
            fetchedAt: Date().timeIntervalSince1970, refreshed: true)
        let operation = Task {
            try await coordinator.install(fresh, client: client, updating: true) { _ in try? await writer.delete(id: "telegram-testpack") }
        }
        await #expect(throws: LibraryError.self) { try await operation.value }
        #expect(try reader.snapshot().packs.isEmpty)
    }

    @Test func cacheClearPreservesInstalledFilesAndRefusesActiveJob() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LibraryReader(root: root.appendingPathComponent("library")), webp = try fixture("alpha-lossless")
        let writer = LibraryWriter(reader: reader), jobs = root.appendingPathComponent("jobs")
        let coordinator = ImportCoordinator(writer: writer, root: jobs)
        FixtureURLProtocol.respond = { _ in (200, webp, [:]) }
        try await coordinator.install(pack(), client: client()) { _ in }
        let snapshot = try reader.snapshot(), index = try reader.index()
        let job = try await ImportJobCache.shared.begin(root: jobs, key: String(repeating: "d", count: 64))
        try Data("cache".utf8).write(to: job.appendingPathComponent("temp"))
        await #expect(throws: StickerImportError.self) { try await ImportJobCache.shared.clear(root: jobs, writer: writer) }
        await ImportJobCache.shared.end(root: jobs)
        try await ImportJobCache.shared.clear(root: jobs, writer: writer)
        #expect(!FileManager.default.fileExists(atPath: job.path))
        #expect(try reader.index().libraryRevision == index.libraryRevision)
        #expect(try reader.index().cacheGeneration != nil)
        #expect(try reader.snapshot().packs.map(\.revision) == snapshot.packs.map(\.revision))
        for sticker in snapshot.packs.flatMap(\.stickers) { #expect(PNGValidation.isValid(try Data(contentsOf: reader.file(sticker.pngPath)))) }
    }

}
