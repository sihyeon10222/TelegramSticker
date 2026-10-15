import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PNGValidation {
    static func isValid(_ data: Data) -> Bool {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) == UTType.png.identifier as CFString,
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 1_024, height <= 1_024,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        return true
    }
}
