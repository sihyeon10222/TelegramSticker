import ImageIO
import UIKit

/// Fixtures are bundled independently into the app and keyboard; no shared container is used.
nonisolated
struct SampleSticker: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    var imageURL: URL? = nil
    var thumbnailURL: URL? = nil
    var animationURL: URL? = nil
    var playbackURL: URL? = nil

    static let all: [SampleSticker] = [
        .init(id: "sample-smile", name: "웃는 얼굴", detail: "투명한 바깥 배경"),
        .init(id: "sample-hearts", name: "겹친 하트", detail: "반투명한 작은 하트"),
        .init(id: "sample-sparkle", name: "반짝 별", detail: "반투명한 빛 테두리")
    ]

    func fileURL(in bundle: Bundle = .main) -> URL? {
        imageURL ?? bundle.url(forResource: id, withExtension: "png")
    }
}

@MainActor
final class SampleStickerImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()
    private var maximumPixelSize: Int

    init(maximumPixelSize: Int = 256) {
        self.maximumPixelSize = max(64, min(256, maximumPixelSize))
    }

    func setMaximumPixelSize(_ value: Int) {
        let size = max(64, min(256, value))
        guard size != maximumPixelSize else { return }
        maximumPixelSize = size
    }

    private func key(for sticker: SampleSticker, pixels: Int) -> NSString {
        "\(sticker.thumbnailURL?.path ?? sticker.imageURL?.path ?? sticker.id):\(pixels)" as NSString
    }

    /// No I/O or decode: safe to use while configuring a cell's first frame.
    func cachedThumbnail(for sticker: SampleSticker, pixels: Int? = nil) -> UIImage? {
        Self.cache.object(forKey: key(for: sticker, pixels: pixels ?? maximumPixelSize))
    }

    func thumbnail(for sticker: SampleSticker, pixels: Int? = nil) -> UIImage? {
        let pixels = pixels ?? maximumPixelSize
        let key = key(for: sticker, pixels: pixels)
        if let image = Self.cache.object(forKey: key) { return image }
        guard let url = sticker.thumbnailURL ?? sticker.fileURL(),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: image)
        Self.cache.setObject(thumbnail, forKey: key,
                        cost: image.bytesPerRow * image.height)
        return thumbnail
    }

    /// Bounded by item count, not a deadline that exposes a partially populated page.
    /// Sources are already-small PNG posters; this does not decode GIF frames.
    func preparePosters<S: Sequence>(for stickers: S, limit: Int) where S.Element == SampleSticker {
        for sticker in stickers.prefix(max(0, limit)) { _ = thumbnail(for: sticker) }
    }

    func thumbnailAsync(for sticker: SampleSticker, pixels: Int? = nil) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let pixels = pixels ?? maximumPixelSize
        if let image = cachedThumbnail(for: sticker, pixels: pixels) { return image }
        guard let url = sticker.thumbnailURL ?? sticker.fileURL() else { return nil }
        let image = await StickerThumbnailDecoder.shared.image(url: url, pixels: pixels)
        guard !Task.isCancelled, let image else { return nil }
        let thumbnail = UIImage(cgImage: image)
        Self.cache.setObject(thumbnail, forKey: key(for: sticker, pixels: pixels), cost: image.bytesPerRow * image.height)
        return thumbnail
    }

    func removeAll() { Self.cache.removeAllObjects() }
}
