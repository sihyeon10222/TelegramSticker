import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum GIFValidation {
    static func isValid(_ data: Data) -> Bool {
        guard validHeader(data), data.count >= 14, data.last == 0x3b else { return false }
        return validate(CGImageSourceCreateWithData(data as CFData, nil))
    }
    static func isValid(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 10), validHeader(header),
              let size = try? handle.seekToEnd(), size >= 14,
              (try? handle.seek(toOffset: size - 1)) != nil,
              (try? handle.read(upToCount: 1)) == Data([0x3b]) else { return false }
        return validate(CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary))
    }
    private static func validHeader(_ data: Data) -> Bool {
        let header = Array(data.prefix(10))
        guard header.count == 10, ["GIF87a", "GIF89a"].contains(String(data: data.prefix(6), encoding: .ascii) ?? "") else { return false }
        return (1...512).contains(Int(header[6]) | Int(header[7]) << 8) &&
            (1...512).contains(Int(header[8]) | Int(header[9]) << 8)
    }
    private static func validate(_ source: CGImageSource?) -> Bool {
        guard let source, CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetStatus(source) == .statusComplete,
              (2...300).contains(CGImageSourceGetCount(source)) else { return false }
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...512).contains(width), (1...512).contains(height),
                  let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return false }
            let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            guard delay.isFinite, delay >= 0.01, delay <= 10.2 else { return false }
            duration += delay
        }
        return duration <= 10.2 && CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: false] as CFDictionary) != nil
    }
}
