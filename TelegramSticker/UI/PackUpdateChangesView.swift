import SwiftUI

/// Shared by update review and the import fallback. Visible remote previews reuse the gallery media cache.
struct PackUpdateChangesView: View {
    let entry: PackUpdateEntry
    let client: WorkerClient?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 12)]

    var body: some View {
        let difference = entry.difference
        VStack(alignment: .leading, spacing: 16) {
            if difference.titleChanged {
                Text("팩 이름: \(entry.installed.title) → \(entry.remote.title)").font(.subheadline)
            }
            if difference.orderChanged { Text("스티커 순서가 변경돼요.").font(.subheadline) }
            remoteGroup("추가", stickers: difference.added)
            if !difference.removed.isEmpty {
                Text("삭제 \(difference.removed.count)개").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(difference.removed) { record in
                        localPreview(record)
                    }
                }
            }
            if !difference.changed.isEmpty {
                Text("변경 \(difference.changed.count)개").font(.headline)
                ForEach(difference.changed) { remote in
                    if let old = entry.installed.stickers.first(where: { $0.id == remote.id }) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack { Text("이전").font(.caption); localPreview(old) }
                            Image(systemName: "arrow.right").padding(.top, 40).accessibilityHidden(true)
                            VStack {
                                Text("변경 후").font(.caption)
                                if old.sourceFormat == remote.format {
                                    localPreview(old, name: remote.emoji ?? "스티커")
                                } else {
                                    remotePreview(remote)
                                    Text(remote.format).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: 300)
                    }
                }
            }
            remoteGroup("미설치 항목 복구", stickers: difference.recovery)
        }
    }

    @ViewBuilder private func remoteGroup(_ title: String, stickers: [RemoteSticker]) -> some View {
        if !stickers.isEmpty {
            Text("\(title) \(stickers.count)개").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(stickers) { sticker in
                    remotePreview(sticker)
                }
            }
        }
    }

    @ViewBuilder private func remotePreview(_ sticker: RemoteSticker) -> some View {
        if let client {
            GalleryStickerPreview(pack: entry.remote.name, sticker: sticker, client: client, visible: true)
        } else {
            RemoteStickerPreview(pack: entry.remote.name, sticker: sticker, client: nil)
        }
    }

    private func localPreview(_ record: StickerRecord, name: String? = nil) -> some View {
        let reader = try? LibraryReader.shared()
        let sticker = Sticker(id: entry.id + "." + record.id, name: record.name, detail: entry.installed.title,
            thumbnailURL: (try? reader?.file(record.thumbnailPath)) ?? nil,
            animationURL: (record.playbackPath ?? record.animationPath).flatMap { try? reader?.file($0) })
        return VStack(spacing: 4) {
            StickerLargePreview(sticker: sticker, pixels: 120, paused: scenePhase != .active || reduceMotion)
                .padding(6).frame(height: 64).frame(maxWidth: .infinity)
                .background(Color(uiColor: .tertiarySystemFill).opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            Text(name ?? record.name).font(.caption2).lineLimit(1)
            Text(record.sourceFormat ?? record.format).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
