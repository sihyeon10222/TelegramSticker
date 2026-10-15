import SwiftUI
import ImageIO

struct GalleryStickerPreview: View {
    let pack: String
    let sticker: RemoteSticker
    let client: WorkerClient
    let visible: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var cache = GalleryPreviewState.shared
    @State private var files: GalleryPreviewFiles?
    private var runnable: Bool { visible && scenePhase == .active && ImportActivity.shared.count == 0 && !cache.maintaining }
    private var key: String { GalleryPreviewStore.key(pack: pack, sticker: sticker) }
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let files, files.poster != nil || files.animation != nil {
                    GalleryPlayback(files: files, paused: !runnable || reduceMotion)
                } else {
                    Image(systemName: sticker.format == "static" ? "photo" : "play.square").foregroundStyle(.secondary)
                }
            }
            .padding(4).frame(height: 64).frame(maxWidth: .infinity)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                if sticker.format != "static" { Text("GIF").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).padding(4) }
            }
            Text(sticker.emoji ?? "스티커").font(.caption2).lineLimit(1)
        }
        .task(id: "\(runnable)-\(reduceMotion)-\(cache.generation)") {
            await GalleryPreviewStore.shared.setVisible(key, runnable)
            guard runnable else { return }
            do {
                let poster = try await GalleryPreviewStore.shared.files(pack: pack, sticker: sticker, client: client, animate: false)
                try Task.checkCancellation()
                files = poster
                if sticker.format != "static", !reduceMotion {
                    let animated = try await GalleryPreviewStore.shared.files(pack: pack, sticker: sticker, client: client, animate: true)
                    try Task.checkCancellation()
                    files = animated
                }
            } catch is CancellationError { return }
            catch { DownloadDiagnostics.shared.record("GALLERY_PREVIEW " + DownloadDiagnostics.errorDetails(error)) }
        }
        .onChange(of: cache.generation) { _, _ in files = nil }
        .onChange(of: cache.maintaining) { _, maintaining in if maintaining { files = nil } }
        .onDisappear { Task { await GalleryPreviewStore.shared.setVisible(key, false) } }
    }
}

private struct GalleryPlayback: UIViewRepresentable {
    let files: GalleryPreviewFiles
    let paused: Bool
    func makeUIView(context: Context) -> GIFPlaybackView {
        let view = GIFPlaybackView()
        view.contentMode = .scaleAspectFit; view.clipsToBounds = true
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GIFPlaybackView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 64, height: proposal.height ?? 64)
    }
    func updateUIView(_ view: GIFPlaybackView, context: Context) {
        view.playbackPaused = paused
        let id = (files.poster?.path ?? "") + "|" + (files.animation?.path ?? "")
        guard context.coordinator.id != id else { return }
        context.coordinator.id = id; context.coordinator.task?.cancel()
        view.configure(url: files.animation, poster: nil, pixels: 96, repeatForever: true)
        let poster = files.poster
        context.coordinator.task = Task { @MainActor [weak view] in
            let image = await Task.detached { () -> CGImage? in
                guard let poster, let source = CGImageSourceCreateWithURL(poster as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 96, kCGImageSourceShouldCache: false] as CFDictionary)
            }.value
            guard !Task.isCancelled, context.coordinator.id == id else { return }
            view?.setPoster(image.map { UIImage(cgImage: $0) })
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var id: String?; var task: Task<Void, Never>? }
    static func dismantleUIView(_ view: GIFPlaybackView, coordinator: Coordinator) { coordinator.task?.cancel(); view.stop() }
}
