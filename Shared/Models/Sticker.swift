import Foundation
import ImageIO
import UIKit

/// Metadata stays cheap to enumerate. Installed paths are validated when a caller
/// requests a URL to display or copy, rather than scanning every asset at startup.
nonisolated
struct Sticker: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    private let image: File?
    private let thumbnail: File?
    private let animation: File?
    private let playback: File?

    private enum File: Equatable, Sendable {
        case direct(URL)
        case library(root: URL, path: String)

        var identity: String {
            switch self {
            case .direct(let url): return url.path
            case .library(let root, let path): return root.appendingPathComponent(path).path
            }
        }

        var resolvedURL: URL? {
            switch self {
            case .direct(let url): return url
            case .library(let root, let path): return try? LibraryReader(root: root).file(path)
            }
        }
    }

    init(id: String, name: String, detail: String, imageURL: URL? = nil,
         thumbnailURL: URL? = nil, animationURL: URL? = nil, playbackURL: URL? = nil) {
        self.id = id; self.name = name; self.detail = detail
        image = imageURL.map(File.direct)
        thumbnail = thumbnailURL.map(File.direct)
        animation = animationURL.map(File.direct)
        playback = playbackURL.map(File.direct)
    }

    init(id: String, name: String, detail: String, reader: LibraryReader,
         imagePath: String? = nil, thumbnailPath: String? = nil,
         animationPath: String? = nil, playbackPath: String? = nil) {
        self.id = id; self.name = name; self.detail = detail
        image = imagePath.map { .library(root: reader.root, path: $0) }
        thumbnail = thumbnailPath.map { .library(root: reader.root, path: $0) }
        animation = animationPath.map { .library(root: reader.root, path: $0) }
        playback = playbackPath.map { .library(root: reader.root, path: $0) }
    }

    var imageURL: URL? { image?.resolvedURL }
    var thumbnailURL: URL? { thumbnail?.resolvedURL }
    var animationURL: URL? { animation?.resolvedURL }
    var playbackURL: URL? { playback?.resolvedURL }
    var isAnimated: Bool { animation != nil }
    /// Cache lookup and presentation metadata must never perform file I/O.
    var thumbnailIdentity: String { thumbnail?.identity ?? image?.identity ?? id }

    func fileURL(in bundle: Bundle = .main) -> URL? {
        if let image { return image.resolvedURL }
        return bundle.url(forResource: id, withExtension: "png")
    }
}
