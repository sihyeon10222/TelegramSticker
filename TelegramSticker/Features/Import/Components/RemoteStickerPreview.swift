import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

struct RemoteStickerPreview: View {
    let pack: String
    let sticker: RemoteSticker
    let client: WorkerClient?
    @State private var image: UIImage?
    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(systemName: sticker.format == "static" ? "photo" : "play.square").foregroundStyle(.secondary) }
            }.padding(6).frame(height: 64).frame(maxWidth: .infinity)
                .background(Color(uiColor: .tertiarySystemFill).opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if sticker.format != "static" {
                        Text("GIF").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).padding(4)
                    }
                }
            Text(sticker.emoji ?? "스티커").font(.caption2).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .task(id: sticker.id) {
            guard sticker.hasThumbnail, let client else { return }
            do {
                let data = try await client.asset(pack: pack, sticker: sticker, thumbnail: true)
                let decoded = await Task.detached { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceGetCount(source) == 1,
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 1024, height <= 1024 else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 160
                    ] as CFDictionary)
                }.value
                guard !Task.isCancelled else { return }
                image = decoded.map { UIImage(cgImage: $0) }
            } catch { image = nil }
        }
    }
}
