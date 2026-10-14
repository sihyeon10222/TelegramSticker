import Foundation
import ImageIO

/// Serializes file reads/decodes, so fast scrolling cannot launch an unbounded decoder fan-out.
actor StickerThumbnailDecoder {
    static let shared = StickerThumbnailDecoder()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.totalCostLimit = 8 * 1024 * 1024 }
    func image(url: URL, pixels: Int) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let key = "\(url.path):\(pixels)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        guard !Task.isCancelled else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
    func clear() { cache.removeAllObjects() }
}
