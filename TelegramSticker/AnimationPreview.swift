import SwiftUI
import UIKit
import ImageIO

struct StickerLargePreview: UIViewRepresentable {
    let sticker: SampleSticker
    var pixels: Int = 256
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
        let renderingID = sticker.id + ":\(pixels)"
        guard context.coordinator.id != renderingID else { return }
        context.coordinator.id = renderingID
        context.coordinator.task?.cancel()
        view.configure(url: sticker.animationURL, poster: nil, pixels: pixels)
        let id = renderingID, url = sticker.fileURL()
        context.coordinator.task = Task { @MainActor [weak view] in
            let image = await Task.detached { () -> CGImage? in
                guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary)
            }.value
            guard !Task.isCancelled, context.coordinator.id == id else { return }
            view?.setPoster(image.map { UIImage(cgImage: $0) })
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var id: String?; var task: Task<Void, Never>? }
    static func dismantleUIView(_ view: GIFPlaybackView, coordinator: Coordinator) { coordinator.task?.cancel(); view.stop() }
}

struct AnimationPreview: View {
    let sticker: SampleSticker
    var body: some View { StickerLargePreview(sticker: sticker).frame(height: 240).padding() }
}
