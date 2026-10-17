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
            coordinator.animationConfigured = false
            view.accessibilityLabel = sticker.name
            view.configure(url: nil, poster: coordinator.images.cachedThumbnail(for: sticker, pixels: pixels), pixels: pixels)
            coordinator.task = Task { @MainActor [weak view] in
                let poster = await coordinator.images.thumbnailAsync(for: sticker, pixels: pixels)
                guard !Task.isCancelled else { return }
                view?.setPoster(poster ?? UIImage(systemName: "exclamationmark.triangle"))
            }
        }
        // Newly arriving cells need only a poster while scrolling. Keep the current
        // frame on already configured cells and resume their timeline when idle.
        if !paused, !coordinator.animationConfigured {
            coordinator.animationConfigured = true
            view.configure(url: sticker.animationURL, poster: view.image, pixels: pixels, repeatForever: true)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        let images = StickerImages()
        var sticker: Sticker?
        var pixels: Int?
        var animationConfigured = false
        var task: Task<Void, Never>?
    }
    static func dismantleUIView(_ view: GIFPlaybackView, coordinator: Coordinator) { coordinator.task?.cancel(); view.stop() }
}

struct AnimationPreview: View {
    let sticker: Sticker
    var body: some View { StickerLargePreview(sticker: sticker).frame(height: 240).padding() }
}
