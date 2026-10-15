import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum KeyboardPlaybackBuilder {
    /// Resample the timeline, not the playback duration. Image I/O composites GIF disposal frames.
    static func build(from url: URL, to output: URL, pixels: Int = 96, fps: Int = 15) throws {
        guard GIFValidation.isValid(url: url), let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { throw LibraryError.invalidImage }
        let count = CGImageSourceGetCount(source)
        var ends: [Double] = [], duration = 0.0
        for i in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            ends.append(duration)
        }
        let samples = max(2, min(count, fps > 15 ? 300 : 150, Int(ceil(duration * Double(fps) - 0.000001))))
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, samples, nil) else { throw LibraryError.invalidImage }
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: output) } }
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let loop = (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int ?? 0
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loop]] as CFDictionary)
        for sample in 0..<samples {
            try Task.checkCancellation()
            try autoreleasepool {
                let time = duration * Double(sample) / Double(samples)
                let index = ends.firstIndex { $0 > time } ?? count - 1
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                    kCGImageSourceShouldCache: false
                ] as CFDictionary) else { throw LibraryError.invalidImage }
                let ticks = max(1, Int((duration * Double(sample + 1) / Double(samples) * 100).rounded())
                    - Int((duration * Double(sample) / Double(samples) * 100).rounded()))
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: Double(ticks) / 100, kCGImagePropertyGIFUnclampedDelayTime: Double(ticks) / 100
                ]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination), GIFValidation.isValid(url: output) else { throw LibraryError.invalidImage }
        complete = true
    }
}
