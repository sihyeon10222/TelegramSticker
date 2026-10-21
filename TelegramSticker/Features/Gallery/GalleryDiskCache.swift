import Foundation
import ImageIO

/// Local-only cold-start snapshot. Never requests metadata, downloads or conversion.
nonisolated struct GalleryCachedCard: Sendable {
    let pack: RemotePack
    let previews: [Preview]
    struct Preview: Sendable {
        let sticker: RemoteSticker
        let files: GalleryPreviewFiles
        let poster: CGImage
    }
}

nonisolated enum GalleryDiskCache {
    static func read(names: [String]) async -> [GalleryCachedCard] {
        let fm = FileManager.default
        let root = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("GalleryPreviews/v1")
        // Resolve the installed library once for the whole batch, rather than per preview.
        let reader = try? LibraryReader.shared()
        let library: LibrarySnapshot?
        if let reader { library = try? await LibrarySnapshotLoader.shared.load(reader: reader).snapshot }
        else { library = nil }
        return names.compactMap { name in
            guard let pack = GalleryMetadataStore.savedPack(name: name) else { return nil }
            let installed = library?.packs.first { $0.telegramName == name }
            let previews = pack.stickers.prefix(3).compactMap { sticker -> GalleryCachedCard.Preview? in
                let key = GalleryPreviewStore.key(pack: name, sticker: sticker)
                let png = root.appendingPathComponent(key + ".png")
                let gif = root.appendingPathComponent(key + ".gif")
                var poster = fm.fileExists(atPath: png.path) ? png : nil
                var animation = sticker.format != "static" && fm.fileExists(atPath: gif.path) ? gif : nil
                if poster == nil, let record = installed?.stickers.first(where: { $0.id == sticker.id }), let reader {
                    if let file = try? reader.file(record.thumbnailPath), fm.fileExists(atPath: file.path) { poster = file }
                    if let path = record.playbackPath ?? record.animationPath,
                       let file = try? reader.file(path), fm.fileExists(atPath: file.path) { animation = file }
                }
                guard let sourceURL = poster ?? animation,
                      let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 96,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                return GalleryCachedCard.Preview(sticker: sticker,
                    files: GalleryPreviewFiles(poster: poster, animation: animation), poster: image)
            }
            return GalleryCachedCard(pack: pack, previews: previews)
        }
    }
}
