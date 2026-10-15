import Foundation
import Testing
@testable import TelegramSticker

@MainActor
struct StorageQuotaTests {
    @Test func validGIFOverEightMiBAndPackOver128MiBInstallAndCopy() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let input = try #require(bundle.url(forResource: "moving-circle", withExtension: "tgs") ?? bundle.url(forResource: "moving-circle", withExtension: "tgs", subdirectory: "Fixtures"))
        let converted = try await TGSConverter.convert(Data(contentsOf: input))
        defer { try? FileManager.default.removeItem(at: converted.file) }
        // Legal comment extension makes a valid large GIF without allocating giant decoded canvases.
        var data = converted.gif; data.removeLast(); data.append(contentsOf: [0x21, 0xfe])
        for _ in 0..<37_000 { data.append(255); data.append(Data(repeating: 32, count: 255)) }
        data.append(contentsOf: [0, 0x3b])
        #expect(data.count > 8 * 1024 * 1024)
        let gif = root.appendingPathComponent("large.gif"), png = root.appendingPathComponent("poster.png")
        try data.write(to: gif); try converted.poster.write(to: png)
        #expect(GIFValidation.isValid(url: gif))
        let reader = LibraryReader(root: root.appendingPathComponent("library")), writer = LibraryWriter(reader: LibraryReader(root: root.appendingPathComponent("library")))
        let inputs = (0..<15).map { LocalStickerInput(id: "large-\($0)", name: "큰 GIF", url: png, sourceFormat: "animated", animationURL: gif) }
        try await writer.install(id: "large-pack", title: "128MiB 초과", stickers: inputs)
        let pack = try #require(reader.snapshot().packs.first)
        #expect(pack.stickers.count == 15 && data.count * 15 > 128 * 1024 * 1024)
        var copied = 0
        let service = StickerCopyService(writeGIF: { copied = $0.count })
        #expect(service.copy(Sticker(id: "large", name: "큰 GIF", detail: "", imageURL: png, animationURL: gif), isAllowed: true) == .copied)
        #expect(copied == data.count)
        #expect(pack.stickers.allSatisfy { $0.playbackPath != nil })
        try await writer.clearDisposableData()
        #expect(try reader.snapshot().packs.first?.stickers.count == 15)
    }
}
