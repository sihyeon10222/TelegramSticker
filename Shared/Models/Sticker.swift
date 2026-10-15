import Foundation
import ImageIO
import UIKit

/// File references for an installed sticker or a bundled fixture; shared by app and keyboard.
nonisolated
struct Sticker: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    var imageURL: URL? = nil
    var thumbnailURL: URL? = nil
    var animationURL: URL? = nil
    var playbackURL: URL? = nil

    func fileURL(in bundle: Bundle = .main) -> URL? {
        imageURL ?? bundle.url(forResource: id, withExtension: "png")
    }
}
