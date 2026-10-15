import Foundation
import ImageIO
import UniformTypeIdentifiers

actor StaticImageConverter {
    func png(from data: Data) throws -> Data {
        guard data.count <= 20 * 1024 * 1024 else { throw ImportLimitFailure(check: "static_input_bytes", actual: String(data.count), limit: "20971520 bytes") }
        if data.count > 20, String(data: data[0..<4], encoding: .ascii) == "RIFF",
           String(data: data[8..<12], encoding: .ascii) == "WEBP",
           String(data: data[12..<16], encoding: .ascii) == "VP8X", data[20] & 2 != 0 {
            throw StickerImportError.unsupportedFormat
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.webP.identifier, UTType.png.identifier].contains(type),
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 1024, height <= 1024, width * height <= 1_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw StickerImportError.unsupportedFormat }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StickerImportError.unsupportedFormat
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), PNGValidation.isValid(data as Data) else {
            throw StickerImportError.unsupportedFormat
        }
        return data as Data
    }
}
