import AVFoundation
import ImageIO
import UIKit
import Testing
@testable import TelegramSticker

@MainActor
struct AnimationCapabilityTests {
    private func gifDuration(_ source: CGImageSource) -> Double {
        (0..<CGImageSourceGetCount(source)).reduce(0) { total, index in
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return total + ((gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0)
        }
    }
    private func fixture(_ ext: String) throws -> URL {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        return try #require(bundle.url(forResource: "moving-circle", withExtension: ext)
            ?? bundle.url(forResource: "moving-circle", withExtension: ext, subdirectory: "Fixtures"))
    }

    @Test func gifKeepsAdvancingWhileViewportScrollsAndSkipsHiddenPages() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let controller = UIViewController()
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 200, height: 500)
        controller.view.addSubview(scroll)
        let playback = GIFPlaybackView(frame: CGRect(x: 20, y: 60, width: 96, height: 96))
        scroll.addSubview(playback)
        let converted = try await TGSConverter.convert(Data(contentsOf: fixture("tgs")))
        defer { playback.stop(); try? FileManager.default.removeItem(at: converted.file) }
        playback.configure(url: converted.file, poster: nil)
        var frames = Set<Data>()
        for offset in stride(from: 0, through: 40, by: 4) {
            scroll.contentOffset.y = CGFloat(offset)
            #expect(playback.isPlaybackVisible)
            try await Task.sleep(for: .milliseconds(100))
            if let image = playback.image?.pngData() { frames.insert(image) }
        }
        #expect(frames.count > 1, "Visible GIF must keep advancing as its viewport scrolls.")
        let beforeReentry = try #require(playback.image)
        playback.configure(url: converted.file, poster: UIImage(systemName: "star"))
        #expect(playback.image === beforeReentry, "Redisplaying the same GIF must keep its decoded frame, not flash its poster.")
        scroll.isHidden = true
        #expect(!playback.isPlaybackVisible)
        scroll.isHidden = false
        scroll.contentOffset.y = 200
        #expect(!playback.isPlaybackVisible)
        scroll.contentOffset.y = 0
        scroll.transform = CGAffineTransform(translationX: 220, y: 0)
        #expect(!playback.isPlaybackVisible)
        scroll.transform = .identity
        #expect(playback.isPlaybackVisible)
    }

    @Test func tgsProducesMovingTransparentGIFAndPNGPoster() async throws {
        let input = try Data(contentsOf: fixture("tgs"))
        let result = try await TGSConverter.convert(input)
        Attachment.record(result.gif, named: "own-tgs.gif")
        #expect(GIFValidation.isValid(result.gif))
        var oversizedCanvas = result.gif
        oversizedCanvas[6] = 255; oversizedCanvas[7] = 255
        #expect(!GIFValidation.isValid(oversizedCanvas))
        #expect(PNGValidation.isValid(result.poster))
        let source = try #require(CGImageSourceCreateWithData(result.gif as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 30)
        #expect(abs(gifDuration(source) - 1) < 0.02)
        var centers: [Double] = []
        for index in [0, 29] {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            let context = try #require(CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))
            let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            var count = 0, sum = 0
            for pixel in 0..<(512 * 512) where bytes[pixel * 4 + 3] > 0 { count += 1; sum += pixel % 512 }
            #expect(count > 10_000 && count < 100_000)
            centers.append(Double(sum) / Double(max(1, count)))
            #expect(bytes[3] == 0)
        }
        #expect(centers[1] - centers[0] > 100)
    }

    @Test func tgsRejectsInvalidGzipAndTrailingPayload() async throws {
        let input = try Data(contentsOf: fixture("tgs"))
        #expect(throws: StickerImportError.self) { try TGSPayload.decode(Data("broken".utf8)) }
        #expect(throws: StickerImportError.self) { try TGSPayload.decode(input + Data([1])) }
        #expect(throws: StickerImportError.self) { try TGSPayload.decode(Data(input.prefix(30))) }
        #expect(throws: StickerImportError.self) { try TGSPayload.decode(Data(repeating: 0, count: 65 * 1024)) }
    }

    @Test func webMProducesMovingTransparentGIFAndPNGPoster() async throws {
        let input = try Data(contentsOf: fixture("webm"))
        let result = try await WebMConverter().convert(input)
        Attachment.record(result.gif, named: "own-webm.gif")
        #expect(GIFValidation.isValid(result.gif))
        #expect(PNGValidation.isValid(result.poster))
        let source = try #require(CGImageSourceCreateWithData(result.gif as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 30)
        #expect(abs(gifDuration(source) - 1) < 0.02)
        var centers: [Double] = []
        for index in [0, 29] {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            let context = try #require(CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))
            let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            var count = 0, sum = 0
            for pixel in 0..<(512 * 512) where bytes[pixel * 4 + 3] > 0 { count += 1; sum += pixel % 512 }
            #expect(count > 10_000 && count < 100_000)
            #expect(bytes[3] == 0)
            centers.append(Double(sum) / Double(max(1, count)))
        }
        #expect(centers[1] - centers[0] > 100)
    }

    @Test func webMRejectsTruncationAndInvalidContainers() throws {
        let input = try Data(contentsOf: fixture("webm"))
        for bad in [Data(), Data(input.prefix(20)), input + Data([0]), Data(repeating: 0, count: 2 * 1024 * 1024 + 1)] {
            #expect(throws: (any Error).self) { try StickerWebM.parse(bad) }
        }
    }

    @Test func nativeVP9RejectsOversizedBitstreamDespiteSafeContainerDimensions() async throws {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let url = try #require(bundle.url(forResource: "oversized-bitstream", withExtension: "webm")
            ?? bundle.url(forResource: "oversized-bitstream", withExtension: "webm", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        #expect(try StickerWebM.parse(data).width == 512)
        await #expect(throws: WebMConversionFailure.self) { try await WebMConverter().convert(data) }
    }

    @Test func longerWebMPreservesDurationAndThirtyFPS() async throws {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let url = try #require(bundle.url(forResource: "long-circle", withExtension: "webm")
            ?? bundle.url(forResource: "long-circle", withExtension: "webm", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let video = try StickerWebM.parse(data)
        #expect(video.packets.count == 94)
        let result = try await WebMConverter().convert(data)
        let source = try #require(CGImageSourceCreateWithData(result.gif as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 94)
        #expect(abs(gifDuration(source) - video.duration) < 0.02)
        #expect(GIFValidation.isValid(result.gif))
    }
    @Test func singleVisibleFrameWebMConvertsWithoutChangingTimeline() async throws {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let url = try #require(bundle.url(forResource: "single-frame", withExtension: "webm")
            ?? bundle.url(forResource: "single-frame", withExtension: "webm", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url), video = try StickerWebM.parse(data)
        #expect(video.packets.count == 1)
        let result = try await WebMConverter().convert(data)
        defer { try? FileManager.default.removeItem(at: result.file) }
        #expect(GIFValidation.isValid(url: result.file))
        let source = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(abs(gifDuration(source) - video.duration) < 0.02)
    }

    @Test func keyboardPreviewPreservesDurationAtSmallSizeAndOnDemandDecoder() async throws {
        let result = try await TGSConverter.convert(Data(contentsOf: fixture("tgs")))
        defer { try? FileManager.default.removeItem(at: result.file) }
        let small = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: small) }
        try KeyboardPlaybackBuilder.build(from: result.file, to: small)
        let source = try #require(CGImageSourceCreateWithURL(small as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 15)
        #expect(abs(gifDuration(source) - 1) < 0.02)
        let timeline = try #require(await GIFFrameDecoder.shared.timeline(small))
        #expect(timeline.frame(at: 0) == 0)
        #expect(timeline.frame(at: 0.5) > 0)
        #expect(timeline.frame(at: 1.01) == 0)
        let frame = try #require(await GIFFrameDecoder.shared.frame(small, index: 10, pixels: 96))
        #expect(frame.width <= 96 && frame.height <= 96)
        await GIFFrameDecoder.shared.clear()
    }

    @Test func hundredFPSInputPreservesDurationAndDisclosesFrameAdjustment() async throws {
        let bundle = Bundle(for: FixtureURLProtocol.self)
        let url = try #require(bundle.url(forResource: "hundred-fps", withExtension: "webm")
            ?? bundle.url(forResource: "hundred-fps", withExtension: "webm", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url), video = try StickerWebM.parse(data)
        #expect(video.packets.count == 20)
        let result = try await WebMConverter().convert(data)
        defer { try? FileManager.default.removeItem(at: result.file) }
        let source = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 6)
        #expect(abs(gifDuration(source) - video.duration) < 0.02)
        #expect(result.quality != nil)
    }

}
