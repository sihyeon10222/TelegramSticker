import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers
import CStickerVP9

nonisolated enum WebMContainerFailure: Error, LocalizedError {
    case unsupported(String)
    case timing(frameDuration: Double, declaredDuration: Double?)
    var errorDescription: String? {
        if case .unsupported(let stage) = self { return "WebM 컨테이너를 읽을 수 없어요 (\(stage)). 손상 또는 지원하지 않는 영상 구성이에요." }
        if case .timing(let delay, let duration) = self {
            if let duration, duration > 10.05 { return "원본 영상 길이(\(String(format: "%.2f", duration))초)가 현재 안전한 변환 범위 10초를 초과해요." }
            return "원본 영상의 프레임 시간(\(String(format: "%.4f", delay))초)이 지원 범위를 벗어났어요."
        }
        return nil
    }
}

nonisolated enum WebMConversionFailure: Error, LocalizedError, Equatable {
    case deadline, bitstream, dimensionsOrFrameCount, image, poster, incomplete, output
    var errorDescription: String? {
        if case .deadline = self { return "애니메이션 변환 시간이 오래 걸려 중단했어요. 다른 항목을 사용해 주세요." }
        return "애니메이션 영상을 변환할 수 없어요. 파일의 형식이나 크기를 확인해 주세요."
    }
}

/// A deliberately bounded WebM subset: one VP9 video track, no audio, encryption or lacing.
/// Unknown-sized Segment is accepted; unknown-sized nested elements are rejected.
nonisolated struct StickerWebM {
    struct Packet { let time: Double; let color: Data; let alpha: Data? }
    let width: Int
    let height: Int
    let duration: Double
    let packets: [Packet]
    private struct Element { let id: UInt64; let range: Range<Int> }
    private struct Parser {
        let bytes: [UInt8]
        var elements = 0
        mutating func vint(_ cursor: inout Int, end: Int, id: Bool = false) throws -> (UInt64, Bool) {
            guard cursor < end, bytes[cursor] != 0 else { throw StickerImportError.unsupportedFormat }
            let first = bytes[cursor], length = first.leadingZeroBitCount + 1
            guard length <= (id ? 4 : 8), length <= end - cursor else { throw StickerImportError.unsupportedFormat }
            var value = UInt64(id ? first : first & (0xff >> length))
            for i in 1..<length { value = value << 8 | UInt64(bytes[cursor + i]) }
            cursor += length
            return (value, !id && value == (UInt64(1) << (7 * length)) - 1)
        }
        mutating func children(_ range: Range<Int>) throws -> [Element] {
            var cursor = range.lowerBound, result: [Element] = []
            while cursor < range.upperBound {
                elements += 1
                guard elements <= 10_000 else { throw ImportLimitFailure(check: "webm_elements", actual: String(elements), limit: "10000 elements") }
                let (id, _) = try vint(&cursor, end: range.upperBound, id: true)
                let (size, unknown) = try vint(&cursor, end: range.upperBound)
                guard (!unknown || id == 0x18538067), unknown || size <= UInt64(range.upperBound - cursor) else {
                    throw StickerImportError.unsupportedFormat
                }
                let end = unknown ? range.upperBound : cursor + Int(size)
                result.append(Element(id: id, range: cursor..<end)); cursor = end
            }
            return result
        }
        func uint(_ e: Element?) throws -> UInt64 {
            guard let e, (1...8).contains(e.range.count) else { throw StickerImportError.unsupportedFormat }
            return e.range.reduce(UInt64(0)) { $0 << 8 | UInt64(bytes[$1]) }
        }
        func string(_ e: Element?) -> String? { e.flatMap { String(bytes: bytes[$0.range], encoding: .utf8) } }
        func number(_ e: Element?) throws -> Double? {
            guard let e else { return nil }
            let value = try uint(e)
            if e.range.count == 4 { return Double(Float(bitPattern: UInt32(value))) }
            if e.range.count == 8 { return Double(bitPattern: value) }
            throw StickerImportError.unsupportedFormat
        }
    }
    static func parse(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else { throw ImportLimitFailure(check: "webm_input_bytes", actual: String(data.count), limit: "1...20971520 bytes") }
        var stage = "header"
        do {
        var p = Parser(bytes: Array(data))
        let top = try p.children(0..<data.count)
        guard let header = top.first(where: { $0.id == 0x1a45dfa3 }),
              let segment = top.first(where: { $0.id == 0x18538067 }),
              top.filter({ $0.id == 0x18538067 }).count == 1 else { throw StickerImportError.unsupportedFormat }
        let head = try p.children(header.range)
        guard p.string(head.first { $0.id == 0x4282 }) == "webm" else { throw StickerImportError.unsupportedFormat }
        stage = "tracks"
        let children = try p.children(segment.range)
        guard let tracks = children.first(where: { $0.id == 0x1654ae6b }),
              let info = children.first(where: { $0.id == 0x1549a966 }) else { throw StickerImportError.unsupportedFormat }
        let trackEntries = try p.children(tracks.range).filter { $0.id == 0xae }
        guard trackEntries.count == 1 else { throw StickerImportError.unsupportedFormat }
        let track = try p.children(trackEntries[0].range)
        let trackID = try p.uint(track.first { $0.id == 0xd7 })
        guard trackID > 0, try p.uint(track.first { $0.id == 0x83 }) == 1,
              p.string(track.first { $0.id == 0x86 }) == "V_VP9",
              !track.contains(where: { $0.id == 0x6d80 }),
              let video = track.first(where: { $0.id == 0xe0 }) else { throw StickerImportError.unsupportedFormat }
        let props = try p.children(video.range)
        let w = try p.uint(props.first { $0.id == 0xb0 }), h = try p.uint(props.first { $0.id == 0xba })
        guard (1...512).contains(w), (1...512).contains(h) else { throw ImportLimitFailure(check: "webm_dimensions", actual: "\(w)x\(h)", limit: "1...512 per dimension") }
        let hasAlpha = try props.first(where: { $0.id == 0x53c0 }).map { try p.uint($0) == 1 } ?? false
        stage = "timing"
        let metadata = try p.children(info.range)
        let scale = try metadata.first(where: { $0.id == 0x2ad7b1 }).map { try p.uint($0) } ?? 1_000_000
        guard scale > 0, scale <= 1_000_000_000 else { throw StickerImportError.unsupportedFormat }
        let unit = Double(scale) / 1_000_000_000
        let declared = try p.number(metadata.first { $0.id == 0x4489 }).map { $0 * unit }
        let defaultDelay = try track.first(where: { $0.id == 0x23e383 }).map { Double(try p.uint($0)) / 1e9 } ?? 1 / 30
        guard defaultDelay.isFinite, defaultDelay >= 0.01 - 0.000001, defaultDelay <= 10.05,
              declared == nil || (declared!.isFinite && declared! > 0 && declared! <= 10.05) else {
            throw WebMContainerFailure.timing(frameDuration: defaultDelay, declaredDuration: declared)
        }
        stage = "blocks"
        var packets: [Packet] = []
        for cluster in children where cluster.id == 0x1f43b675 {
            let entries = try p.children(cluster.range)
            let timestamp = try p.uint(entries.first { $0.id == 0xe7 })
            for entry in entries where entry.id == 0xa3 || entry.id == 0xa0 {
                var block = entry, alpha: Data?
                if entry.id == 0xa0 {
                    let group = try p.children(entry.range)
                    guard let b = group.first(where: { $0.id == 0xa1 }) else { throw StickerImportError.unsupportedFormat }
                    block = b
                    if let additions = group.first(where: { $0.id == 0x75a1 }) {
                        for more in try p.children(additions.range) where more.id == 0xa6 {
                            let parts = try p.children(more.range)
                            let addID = try parts.first(where: { $0.id == 0xee }).map { try p.uint($0) } ?? 1
                            guard addID == 1, alpha == nil, let bytes = parts.first(where: { $0.id == 0xa5 }) else {
                                throw StickerImportError.unsupportedFormat
                            }
                            alpha = Data(p.bytes[bytes.range])
                        }
                    }
                }
                var cursor = block.range.lowerBound
                let (number, unknown) = try p.vint(&cursor, end: block.range.upperBound)
                guard !unknown, number == trackID, block.range.upperBound - cursor > 3 else { throw StickerImportError.unsupportedFormat }
                let relative = Int16(bitPattern: UInt16(p.bytes[cursor]) << 8 | UInt16(p.bytes[cursor + 1]))
                guard p.bytes[cursor + 2] & 0x06 == 0 else { throw StickerImportError.unsupportedFormat }
                let time = (Double(timestamp) + Double(relative)) * unit
                guard time.isFinite, time >= 0, time <= 10.05,
                      packets.last == nil || time > packets.last!.time,
                      !hasAlpha || (alpha != nil && !alpha!.isEmpty), packets.count < 1000 else {
                    throw StickerImportError.unsupportedFormat
                }
                packets.append(Packet(time: time, color: Data(p.bytes[(cursor + 3)..<block.range.upperBound]), alpha: alpha))
            }
        }
        guard !packets.isEmpty, let last = packets.last else { throw StickerImportError.unsupportedFormat }
        stage = "duration"
        let duration = max(declared ?? 0, last.time + defaultDelay)
        guard duration <= 10.05 else { throw StickerImportError.unsupportedFormat }
        return Self(width: Int(w), height: Int(h), duration: duration, packets: packets)
        } catch StickerImportError.unsupportedFormat { throw WebMContainerFailure.unsupported(stage) }
    }
}

/// CPU time excludes OS scheduling/suspension. Used only across synchronous work
/// on the same thread; asynchronous renderers charge one frame at a time.
nonisolated enum ProcessingCPUClock {
    static var seconds: Double {
        var value = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value)
        return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
    }
}

actor WebMConverter {
    func convert(_ data: Data, output: URL? = nil, quality: AnimationQuality = .original) throws -> ConvertedAnimation {
        let video = try StickerWebM.parse(data)
        let deadline = ProcessingCPUClock.seconds + 45
        // Image I/O requires a known nonzero image count. Count visible VP9 frames
        // without allocating RGBA images, then encode using a fresh decoder.
        let sourceCount = try preflight(video, deadline: deadline)
        guard sourceCount > 0 else { throw WebMConversionFailure.incomplete }
        let frameCount = max(2, min(sourceCount, Int(ceil(video.duration * Double(quality.fps)))))
        guard let decoder = sb_vp9_create() else { throw StickerImportError.unsupportedFormat }
        defer { sb_vp9_destroy(decoder) }
        let result = output ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: result) } }
        guard let destination = CGImageDestinationCreateWithURL(result as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw StickerImportError.unsupportedFormat
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var previous: CGImage?, poster: Data?, count = 0, decodedCount = 0
        var timelineStart = 0.0, encodedTicks = 0
        func add(_ image: CGImage, until time: Double) {
            let target = Int(((time - timelineStart) * 100).rounded())
            let ticks = max(1, target - encodedTicks)
            let delay = Double(ticks) / 100
            encodedTicks += ticks
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay
            ]] as CFDictionary)
        }
        for packet in video.packets {
            try Task.checkCancellation()
            guard ProcessingCPUClock.seconds < deadline else { throw WebMConversionFailure.deadline }
            try autoreleasepool {
                var rgba = [UInt8](repeating: 0, count: 512 * 512 * 4), width: Int32 = 0, height: Int32 = 0
                let decoded = packet.color.withUnsafeBytes { color in
                    (packet.alpha ?? Data()).withUnsafeBytes { alpha in
                        sb_vp9_decode(decoder, color.bindMemory(to: UInt8.self).baseAddress, color.count,
                            alpha.bindMemory(to: UInt8.self).baseAddress, alpha.count, &rgba, rgba.count, &width, &height)
                    }
                }
                guard decoded >= 0 else { throw WebMConversionFailure.bitstream }
                if decoded == 0 { return }
                guard width == video.width, height == video.height, decodedCount < sourceCount else { throw WebMConversionFailure.dimensionsOrFrameCount }
                let frameIndex = decodedCount
                decodedCount += 1
                // Keep the first/last and uniformly sample at most 90 frames. Use
                // original timestamps, preserving the full duration of older packs.
                let selectedIndex = count * (sourceCount - 1) / (frameCount - 1)
                if frameIndex != selectedIndex { return }
                guard count < frameCount else { throw WebMConversionFailure.dimensionsOrFrameCount }
                let bytes = Data(rgba.prefix(Int(width * height * 4)))
                guard let provider = CGDataProvider(data: bytes as CFData), let originalImage = CGImage(width: Int(width), height: Int(height),
                    bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw WebMConversionFailure.image }
                let image = try quality.resized(originalImage)
                if let previous { add(previous, until: packet.time) }
                else {
                    timelineStart = packet.time
                    let png = NSMutableData()
                    guard let output = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { throw StickerImportError.unsupportedFormat }
                    CGImageDestinationAddImage(output, image, nil)
                    guard CGImageDestinationFinalize(output) else { throw StickerImportError.unsupportedFormat }
                    poster = png as Data
                }
                previous = image; count += 1
            }
        }
        guard decodedCount == sourceCount, let previous, let poster else { throw WebMConversionFailure.incomplete }
        if sourceCount == 1, count == 1 {
            // Some Telegram video stickers contain one visible frame. Preserve that still timeline
            // as two equal GIF frames rather than rejecting an otherwise valid VP9 file.
            add(previous, until: timelineStart + (video.duration - timelineStart) / 2)
            add(previous, until: video.duration)
        } else {
            guard count == frameCount else { throw WebMConversionFailure.incomplete }
            add(previous, until: video.duration)
        }
        guard CGImageDestinationFinalize(destination), GIFValidation.isValid(url: result), PNGValidation.isValid(poster) else {
            throw WebMConversionFailure.output
        }
        completed = true
        return ConvertedAnimation(file: result, poster: poster, quality: sourceCount > frameCount || max(video.width, video.height) > quality.pixels ? quality.label : nil)
    }

    func diagnostics(_ data: Data) throws -> String {
        let video = try StickerWebM.parse(data)
        let count = try preflight(video, deadline: ProcessingCPUClock.seconds + 45)
        return "packets=\(video.packets.count), visibleFrames=\(count), duration=\(video.duration), size=\(video.width)x\(video.height)"
    }

    private func preflight(_ video: StickerWebM, deadline: Double) throws -> Int {
        guard let decoder = sb_vp9_create() else { throw WebMConversionFailure.bitstream }
        defer { sb_vp9_destroy(decoder) }
        var count = 0
        for packet in video.packets {
            try Task.checkCancellation()
            guard ProcessingCPUClock.seconds < deadline else { throw WebMConversionFailure.deadline }
            var width: Int32 = 0, height: Int32 = 0
            let decoded = packet.color.withUnsafeBytes { color in
                (packet.alpha ?? Data()).withUnsafeBytes { alpha in
                    sb_vp9_decode(decoder, color.bindMemory(to: UInt8.self).baseAddress, color.count,
                        alpha.bindMemory(to: UInt8.self).baseAddress, alpha.count, nil, 0, &width, &height)
                }
            }
            guard decoded >= 0 else { throw WebMConversionFailure.bitstream }
            if decoded == 1 {
                count += 1
                guard width == video.width, height == video.height, count <= 1000 else { throw WebMConversionFailure.dimensionsOrFrameCount }
            }
        }
        return count
    }
}
