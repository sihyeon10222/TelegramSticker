import Foundation
import ImageIO
import Lottie
import UIKit
import UniformTypeIdentifiers
import zlib

nonisolated struct ConvertedAnimation: Sendable {
    let file: URL
    var gif: Data { (try? Data(contentsOf: file)) ?? Data() }
    let poster: Data
    var quality: String? = nil
}

nonisolated enum TGSPayload {
    static func decode(_ data: Data) throws -> Data {
        guard data.count <= 64 * 1024, data.starts(with: [0x1f, 0x8b]) else {
            throw StickerImportError.unsupportedFormat
        }
        let limit = 2 * 1024 * 1024
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw StickerImportError.unsupportedFormat
        }
        defer { inflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: limit + 1)
        let status = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(destination.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.avail_in == 0, stream.total_out <= limit else {
            throw StickerImportError.unsupportedFormat
        }
        return Data(output.prefix(Int(stream.total_out)))
    }
}

/// Conversion runs in the containing app. The keyboard only reads the finished GIF.
@MainActor
enum TGSConverter {
    static func convert(_ data: Data, output: URL? = nil, quality: AnimationQuality = .original) async throws -> ConvertedAnimation {
        let json = try await Task.detached { try TGSPayload.decode(data) }.value
        let object = try JSONSerialization.jsonObject(with: json)
        guard let root = object as? [String: Any],
              let width = root["w"] as? Int, let height = root["h"] as? Int,
              (1...512).contains(width), (1...512).contains(height),
              let rate = root["fr"] as? Double, rate.isFinite, rate > 0, rate <= 60,
              let start = root["ip"] as? Double, let end = root["op"] as? Double,
              start.isFinite, end.isFinite, end > start, (end - start) / rate <= 10.05 else {
            throw StickerImportError.unsupportedFormat
        }
        // Telegram TGS is vector-only. Reject images/text and external resource references.
        var pending: [Any] = [object], nodes = 0
        while let value = pending.popLast() {
            nodes += 1
            // peepo_pepe/😎 is a valid 49,200-byte TGS with 181,917 JSON values.
            // Keep a bounded graph budget alongside the independent 2 MiB inflate cap.
            guard nodes <= 250_000 else { throw ImportLimitFailure(check: "tgs_json_nodes", actual: String(nodes), limit: "250000 nodes") }
            if let dictionary = value as? [String: Any] {
                if dictionary["p"] is String || dictionary["u"] is String ||
                    [2, 5].contains(dictionary["ty"] as? Int ?? -1) {
                    throw StickerImportError.unsupportedFormat
                }
                pending.append(contentsOf: dictionary.values)
            } else if let values = value as? [Any] { pending.append(contentsOf: values) }
        }
        DownloadDiagnostics.shared.record("TGS_PREFLIGHT compressedBytes=\(data.count) inflatedBytes=\(json.count) nodes=\(nodes) nodeLimit=250000 inflateLimit=2097152 dimensions=\(width)x\(height) sourceFPS=\(rate) duration=\((end - start) / rate)s quality=\(quality.label)")
        let animation = try LottieAnimation.from(data: json)
        let view = LottieAnimationView(animation: animation, configuration: LottieConfiguration(renderingEngine: .mainThread))
        let scale = min(1, Double(quality.pixels) / Double(max(width, height)))
        view.frame = CGRect(x: 0, y: 0, width: Double(width) * scale, height: Double(height) * scale)
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        view.layoutIfNeeded()
        let duration = (end - start) / rate
        let count = max(2, min(300, Int(ceil(duration * min(Double(quality.fps), rate)))))
        let result = output ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: result) } }
        guard let destination = CGImageDestinationCreateWithURL(result as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw StickerImportError.unsupportedFormat
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size, format: format)
        var processing = 0.0
        var poster: Data?
        for index in 0..<count {
            try await BackgroundWork.shared.waitForExecution()
            try Task.checkCancellation()
            guard processing < 45 else { throw StickerImportError.conversionTimeout }
            let frameStart = ProcessingCPUClock.seconds
            try autoreleasepool {
                view.currentFrame = start + (end - start) * Double(index) / Double(count)
                view.forceDisplayUpdate()
                guard let image = renderer.image(actions: { view.layer.render(in: $0.cgContext) }).cgImage else {
                    throw StickerImportError.unsupportedFormat
                }
                if index == 0 {
                    let png = NSMutableData()
                    guard let output = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
                        throw StickerImportError.unsupportedFormat
                    }
                    CGImageDestinationAddImage(output, image, nil)
                    guard CGImageDestinationFinalize(output) else { throw StickerImportError.unsupportedFormat }
                    poster = png as Data
                }
                // GIF stores centiseconds. Alternate 3/4 ticks at 30fps instead of
                // truncating every frame to 3 ticks and speeding up the whole clip.
                let ticks = max(1, Int((duration * Double(index + 1) / Double(count) * 100).rounded())
                    - Int((duration * Double(index) / Double(count) * 100).rounded()))
                let delay = Double(ticks) / 100
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay
                ]] as CFDictionary)
            }
            processing += max(0, ProcessingCPUClock.seconds - frameStart)
            await Task.yield()
        }
        guard CGImageDestinationFinalize(destination), let poster, PNGValidation.isValid(poster),
              GIFValidation.isValid(url: result) else { throw StickerImportError.unsupportedFormat }
        completed = true
        return ConvertedAnimation(file: result, poster: poster, quality: rate > Double(quality.fps) || scale < 1 ? quality.label : nil)
    }
}
