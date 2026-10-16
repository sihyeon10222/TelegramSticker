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
    @Bindable private var item: GalleryPreviewItem
    init(pack: String, sticker: RemoteSticker, client: WorkerClient, visible: Bool) {
        self.pack = pack; self.sticker = sticker; self.client = client; self.visible = visible
        item = GalleryPreviewState.shared.item(key: GalleryPreviewStore.key(pack: pack, sticker: sticker))
    }
    private var runnable: Bool { visible && scenePhase == .active && ImportActivity.shared.count == 0 && !cache.maintaining }
    private var key: String { GalleryPreviewStore.key(pack: pack, sticker: sticker) }
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let files = item.files, files.poster != nil || files.animation != nil {
                    GalleryPlayback(files: files, poster: item.poster, paused: !runnable || reduceMotion)
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
            item.load(pack: pack, sticker: sticker, client: client, animate: !reduceMotion)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { item.cancel() } }
        .onDisappear { Task { await GalleryPreviewStore.shared.setVisible(key, false) } }
    }
}

private struct GalleryPlayback: UIViewRepresentable {
    let files: GalleryPreviewFiles
    let poster: UIImage?
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
        context.coordinator.id = id
        view.configure(url: files.animation, poster: poster, pixels: 96, repeatForever: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var id: String? }
    static func dismantleUIView(_ view: GIFPlaybackView, coordinator: Coordinator) { view.stop() }
}
