import SwiftUI
import UIKit

struct StickerLargePreview: UIViewRepresentable {
    let sticker: Sticker
    var pixels: Int = 256
    var paused = false
    func makeUIView(context: Context) -> GIFPlaybackView {
        let view = GIFPlaybackView(); view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.accessibilityLabel = sticker.name; view.isAccessibilityElement = true
        view.accessibilityIdentifier = "previewImage"
        return view
    }
    // UIImageView's intrinsic size changes as posters and GIF frames arrive.
    // Keep that size from overriding the preview area proposed by SwiftUI.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GIFPlaybackView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: proposal.height ?? 240)
    }
    func updateUIView(_ view: GIFPlaybackView, context: Context) {
        view.playbackPaused = paused
        let coordinator = context.coordinator
        // Include file URLs so a new installed revision cannot keep an old poster or GIF.
        if coordinator.sticker != sticker || coordinator.pixels != pixels {
            coordinator.task?.cancel()
            coordinator.sticker = sticker
            coordinator.pixels = pixels
            view.accessibilityLabel = sticker.name
            // Configure playback immediately. Poster loading and GIF preparation are
            // independent, so neither scrolling nor a later SwiftUI update starts it.
            view.configure(url: sticker.animationURL,
                poster: coordinator.images.cachedThumbnail(for: sticker, pixels: pixels),
                pixels: pixels, repeatForever: true)
            coordinator.task = Task { @MainActor [weak view] in
                let poster = await coordinator.images.thumbnailAsync(for: sticker, pixels: pixels)
                guard !Task.isCancelled else { return }
                view?.setPoster(poster ?? UIImage(systemName: "exclamationmark.triangle"))
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        let images = StickerImages()
        var sticker: Sticker?
        var pixels: Int?
        var task: Task<Void, Never>?
    }
    static func dismantleUIView(_ view: GIFPlaybackView, coordinator: Coordinator) { coordinator.task?.cancel(); view.stop() }
}
