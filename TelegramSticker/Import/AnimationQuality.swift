import Foundation
import CoreGraphics

nonisolated struct AnimationQuality: Sendable {
    let pixels: Int
    let fps: Int
    static let original = Self(pixels: 512, fps: 30)
    static let fallback = [original, Self(pixels: 384, fps: 24), Self(pixels: 256, fps: 15)]
    var label: String { "\(pixels)px · 최대 \(fps)fps" }
    func resized(_ image: CGImage) throws -> CGImage {
        let scale = min(1, Double(pixels) / Double(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw StickerImportError.unsupportedFormat }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw StickerImportError.unsupportedFormat }
        return result
    }
}
