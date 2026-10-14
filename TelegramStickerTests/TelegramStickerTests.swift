import Foundation
import ImageIO
import Testing
import UIKit
@testable import TelegramSticker

@MainActor
struct TelegramStickerTests {
    @Test func deniedPermissionDoesNotLoadOrWrite() {
        var loads = 0
        var writes = 0
        let copier = StickerCopyService(loadData: { _ in loads += 1; return Data() },
                                        writePNG: { _ in writes += 1 })
        #expect(copier.copyPNG(at: URL(fileURLWithPath: "/unused.png"), isAllowed: false) == .fullAccessRequired)
        #expect(loads == 0)
        #expect(writes == 0)
    }

    @Test func missingResourceDoesNotWrite() {
        var writes = 0
        let copier = StickerCopyService(writePNG: { _ in writes += 1 })
        #expect(copier.copyPNG(at: nil, isAllowed: true) == .fileUnavailable)
        #expect(copier.copyPNG(at: URL(fileURLWithPath: "/nonexistent-sticker.png"), isAllowed: true) == .fileUnavailable)
        #expect(writes == 0)
    }

    @Test func fileReadFailureDoesNotWrite() {
        var writes = 0
        let copier = StickerCopyService(loadData: { _ in throw CocoaError(.fileReadNoPermission) },
                                        writePNG: { _ in writes += 1 })
        #expect(copier.copyPNG(at: URL(fileURLWithPath: "/fixture.png"), isAllowed: true) == .fileUnavailable)
        #expect(writes == 0)
    }

    @Test func invalidAndTruncatedPNGDoNotWrite() throws {
        let url = try #require(SampleSticker.all.first?.fileURL())
        let validData = try Data(contentsOf: url)
        var writes = 0
        for invalidData in [Data(), Data("not a PNG".utf8), Data(validData.prefix(40)), Data(repeating: 0, count: 2_097_153)] {
            let copier = StickerCopyService(loadData: { _ in invalidData }, writePNG: { _ in writes += 1 })
            #expect(copier.copyPNG(at: url, isAllowed: true) == .invalidPNG)
        }
        #expect(writes == 0)
    }

    @Test func nonPNGImageIsRejected() throws {
        let url = try #require(SampleSticker.all.first?.fileURL())
        let image = try #require(UIImage(contentsOfFile: url.path))
        let jpeg = try #require(image.jpegData(compressionQuality: 0.8))
        var writes = 0
        let copier = StickerCopyService(loadData: { _ in jpeg }, writePNG: { _ in writes += 1 })
        #expect(copier.copyPNG(at: url, isAllowed: true) == .invalidPNG)
        #expect(writes == 0)
    }

    @Test func oversizedDimensionsAreRejected() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1_025, height: 1), format: format).pngData { _ in }
        var writes = 0
        let copier = StickerCopyService(loadData: { _ in data }, writePNG: { _ in writes += 1 })
        #expect(copier.copyPNG(at: URL(fileURLWithPath: "/fixture.png"), isAllowed: true) == .invalidPNG)
        #expect(writes == 0)
    }

    @Test func samplesCopyWithoutReencodingAndRetainAlpha() throws {
        #expect(SampleSticker.all.count == 3)
        for sticker in SampleSticker.all {
            let url = try #require(sticker.fileURL())
            let original = try Data(contentsOf: url)
            var captured: [Data] = []
            let copier = StickerCopyService(writePNG: { captured.append($0) })
            #expect(copier.copyPNG(at: url, isAllowed: true) == .copied)
            #expect(captured == [original])

            let source = try #require(CGImageSourceCreateWithData(original as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 512 && image.height == 512)
            let context = try #require(CGContext(
                data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2_048,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))
            let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            let alphas = stride(from: 3, to: 512 * 512 * 4, by: 4).map { bytes[$0] }
            #expect(alphas.contains(0))
            #expect(alphas.contains(255))
            #expect(alphas.contains { $0 > 0 && $0 < 255 })
        }
    }

    @Test func embeddedKeyboardHasIdenticalSamplesAndOpenAccessConfiguration() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let keyboard = try #require(Bundle(url: plugins.appendingPathComponent("StickerKeyboard.appex")))
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "StickerBridge")
        #expect(keyboard.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "StickerBridge")
        let extensionInfo = try #require(keyboard.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        let attributes = try #require(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        #expect(attributes["RequestsOpenAccess"] as? Bool == true)
        #expect(attributes["IsASCIICapable"] as? Bool == false)
        for sticker in SampleSticker.all {
            let appURL = try #require(sticker.fileURL())
            let keyboardURL = try #require(sticker.fileURL(in: keyboard))
            #expect(try Data(contentsOf: appURL) == Data(contentsOf: keyboardURL))
        }
    }

    @Test func permissionIsEvaluatedForEachCopy() throws {
        let url = try #require(SampleSticker.all.first?.fileURL())
        var writes = 0
        let copier = StickerCopyService(writePNG: { _ in writes += 1 })
        #expect(copier.copyPNG(at: url, isAllowed: true) == .copied)
        #expect(copier.copyPNG(at: url, isAllowed: false) == .fullAccessRequired)
        #expect(copier.copyPNG(at: url, isAllowed: true) == .copied)
        #expect(writes == 2)
    }
}
