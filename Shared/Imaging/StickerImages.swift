import Foundation
import ImageIO
import UIKit

@MainActor
final class StickerImages {
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

    private func key(for sticker: Sticker, pixels: Int) -> NSString {
        "\(sticker.thumbnailIdentity):\(pixels)" as NSString
    }

    /// No I/O or decode: safe to use while configuring a cell's first frame.
    func cachedThumbnail(for sticker: Sticker, pixels: Int? = nil) -> UIImage? {
        Self.cache.object(forKey: key(for: sticker, pixels: pixels ?? maximumPixelSize))
    }

    func thumbnail(for sticker: Sticker, pixels: Int? = nil) -> UIImage? {
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
    func preparePosters<S: Sequence>(for stickers: S, limit: Int) where S.Element == Sticker {
        for sticker in stickers.prefix(max(0, limit)) { _ = thumbnail(for: sticker) }
    }

    func thumbnailAsync(for sticker: Sticker, pixels: Int? = nil) async -> UIImage? {
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
