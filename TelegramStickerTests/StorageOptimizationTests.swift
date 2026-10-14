import Foundation
import ImageIO
import Testing
@testable import TelegramSticker

@MainActor
struct StorageOptimizationTests {
    private func fixture() async throws -> (LibraryReader, LibraryWriter) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let url = try #require(bundle.url(forResource: "alpha-lossless", withExtension: "webp") ?? bundle.url(forResource: "alpha-lossless", withExtension: "webp", subdirectory: "Fixtures"))
        let png = try await StaticImageConverter().png(from: Data(contentsOf: url))
        let source = root.appendingPathComponent("source.png")
        try png.write(to: source)
        let reader = LibraryReader(root: root.appendingPathComponent("library")), writer = LibraryWriter(reader: LibraryReader(root: root.appendingPathComponent("library")))
        try await writer.install(id: "first", title: "첫 팩", stickers: [.init(id: "one", name: "투명", url: source)])
        return (reader, writer)
    }
    @Test func optimizationSavesSpacePreservesAlphaAndIDsAndDoesNotRepeat() async throws {
        let (reader, writer) = try await fixture()
        defer { try? FileManager.default.removeItem(at: reader.root.deletingLastPathComponent()) }
        let before = try reader.snapshot().packs[0]
        let result = try await writer.optimizeStorage()
        #expect(result.saved > 0 && result.optimizedPacks == 1 && result.failures.isEmpty)
        let after = try reader.snapshot().packs[0]
        #expect(after.id == before.id && after.stickers.map(\.id) == before.stickers.map(\.id))
        #expect(!FileManager.default.fileExists(atPath: try reader.file("packs/first/\(before.revision)").path))
        let source = try #require(CGImageSourceCreateWithURL(reader.file(after.stickers[0].pngPath) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 384 && image.height == 384)
        #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst)
        let again = try await writer.optimizeStorage()
        #expect(again.saved == 0 && again.optimizedPacks == 0)
        #expect(try reader.snapshot().packs[0].revision == after.revision)
    }
    @Test func failedPublicationKeepsOriginalFilesAndIndex() async throws {
        let (reader, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: reader.root.deletingLastPathComponent()) }
        let index = try Data(contentsOf: reader.file("index.json"))
        let writer = LibraryWriter(reader: reader, publish: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let result = try await writer.optimizeStorage()
        #expect(result.saved == 0 && result.failures.count == 1)
        #expect(try Data(contentsOf: reader.file("index.json")) == index)
        let record = try reader.snapshot().packs[0].stickers[0]
        #expect(try PNGValidation.isValid(Data(contentsOf: reader.file(record.pngPath))))
    }
    @Test func comparisonDoesNotChangeInstalledFilesAndAppliesOnlySelectedPack() async throws {
        let (reader, writer) = try await fixture()
        defer { try? FileManager.default.removeItem(at: reader.root.deletingLastPathComponent()) }
        let first = try reader.snapshot().packs[0]
        try await writer.install(id: "second", title: "두 번째", stickers: writer.inputs(for: first))
        let before = try Data(contentsOf: reader.file("index.json"))
        let secondRevision = try reader.snapshot().packs[1].revision
        let draft = try await writer.prepareOptimization(packIDs: ["first"], stickerIDs: ["first.one"], profile: .balanced, progress: { _, _ in })
        defer { try? FileManager.default.removeItem(at: draft.root) }
        #expect(draft.saved > 0 && draft.comparisons.count == 1)
        #expect(try Data(contentsOf: reader.file("index.json")) == before)
        let item = draft.comparisons[0]
        #expect(item.after < item.before)
        let oldSource = try #require(CGImageSourceCreateWithURL(item.original.imageURL! as CFURL, nil))
        let newSource = try #require(CGImageSourceCreateWithURL(item.optimized.imageURL! as CFURL, nil))
        #expect(try #require(CGImageSourceCreateImageAtIndex(oldSource, 0, nil)).width == 512)
        #expect(try #require(CGImageSourceCreateImageAtIndex(newSource, 0, nil)).width == 384)
        let receipt = try await writer.applyOptimization(draft)
        #expect(receipt.saved == draft.saved && receipt.optimizedPacks == 1 && receipt.failures.isEmpty)
        // Original stays available in the isolated comparison even after installed assets change.
        #expect(FileManager.default.fileExists(atPath: item.original.imageURL!.path))
        #expect(FileManager.default.fileExists(atPath: item.optimized.imageURL!.path))
        #expect(try reader.snapshot().packs[1].revision == secondRevision)
    }
    @Test func comparisonCannotOverwriteNewRevisionOrResurrectDeletedPack() async throws {
        let (reader, writer) = try await fixture()
        defer { try? FileManager.default.removeItem(at: reader.root.deletingLastPathComponent()) }
        let draft = try await writer.prepareOptimization(packIDs: ["first"], stickerIDs: nil, profile: .balanced, progress: { _, _ in })
        defer { try? FileManager.default.removeItem(at: draft.root) }
        try await writer.delete(id: "first")
        let result = try await writer.applyOptimization(draft)
        #expect(result.optimizedPacks == 0 && result.failures.count == 1)
        #expect(try reader.snapshot().packs.isEmpty)
    }

    @Test func gifResamplingPreservesTimelineAndLoop() async throws {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let input = try #require(bundle.url(forResource: "moving-circle", withExtension: "tgs") ?? bundle.url(forResource: "moving-circle", withExtension: "tgs", subdirectory: "Fixtures"))
        let animation = try await TGSConverter.convert(Data(contentsOf: input))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: animation.file); try? FileManager.default.removeItem(at: output) }
        try KeyboardPlaybackBuilder.build(from: animation.file, to: output, pixels: 256, fps: 15)
        func metadata(_ url: URL) throws -> (Double, Int) {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            var duration = 0.0
            for index in 0..<CGImageSourceGetCount(source) {
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            }
            let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
            return (duration, (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int ?? 0)
        }
        let before = try metadata(animation.file), after = try metadata(output)
        #expect(abs(before.0 - after.0) < 0.011 && before.1 == after.1)
        #expect(GIFValidation.isValid(url: output))
    }
}
