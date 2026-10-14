import SwiftUI
import UIKit

@MainActor @Observable
final class LibraryModel {
    var packs: [PackManifestV1] = []
    var damagedPacks: [PackReference] = []
    var message: String?
    var isBusy = false
    var isAvailable = false
    private(set) var reader: LibraryReader?
    private(set) var writer: LibraryWriter?

    init(reader initialReader: LibraryReader? = nil, writer initialWriter: LibraryWriter? = nil) {
        do {
            let reader = try initialReader ?? LibraryReader.shared()
            self.reader = reader
            writer = initialWriter ?? (initialReader == nil ? LibraryWriter.shared : nil)
            isAvailable = true
            // Published manifests are ready to display; maintenance must not gate the first frame.
            let snapshot = try reader.snapshot(resolvingFiles: false)
            packs = snapshot.packs
            let available = Set(snapshot.packs.map(\.id))
            damagedPacks = try reader.index().packs.filter { !available.contains($0.id) }
            message = snapshot.warnings.first
        } catch { message = error.localizedDescription }
    }

    func refresh() async {
        guard let reader else { return }
        do {
            let (snapshot, references) = try await Task.detached { (try reader.snapshot(resolvingFiles: false), try reader.index().packs) }.value
            packs = snapshot.packs
            damagedPacks = references.filter { reference in !snapshot.packs.contains { $0.id == reference.id } }
            message = snapshot.warnings.first
        } catch { message = error.localizedDescription }
    }

    func start() async {
        if let writer {
            do { try await writer.recover() } catch { message = error.localizedDescription }
        }
        await refresh()
        if let writer {
            do { try await writer.preparePlaybackFiles(); await refresh() } catch { message = error.localizedDescription }
        }
    }

    func delete(ids: [String]) async {
        guard let writer, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            for id in ids { try await writer.delete(id: id) }
            await refresh()
        } catch { message = error.localizedDescription; await reloadPreservingMessage() }
    }

    func move(from: IndexSet, to: Int) async {
        guard let writer, !isBusy else { return }
        var reordered = packs
        reordered.move(fromOffsets: from, toOffset: to)
        isBusy = true
        defer { isBusy = false }
        do {
            try await writer.reorder(ids: reordered.map(\.id))
            await refresh()
        } catch { message = error.localizedDescription }
    }

    private func reloadPreservingMessage() async {
        let previous = message
        await refresh()
        message = previous
    }

    func stickers(in pack: PackManifestV1) -> [SampleSticker] {
        guard let reader else { return [] }
        return pack.stickers.compactMap { record in
            guard let png = try? reader.file(record.pngPath),
                  let thumbnail = try? reader.file(record.thumbnailPath) else { return nil }
            return SampleSticker(id: "\(pack.id).\(record.id)", name: record.name, detail: pack.title,
                                 imageURL: png, thumbnailURL: thumbnail,
                                 animationURL: record.animationPath.flatMap { try? reader.file($0) })
        }
    }

    func cover(in pack: PackManifestV1) -> SampleSticker? {
        guard let reader, let record = pack.stickers.first,
              let url = try? reader.file(record.thumbnailPath) else { return nil }
        return SampleSticker(id: pack.id, name: pack.title, detail: "", thumbnailURL: url)
    }
}

struct LibraryView: View {
    @State private var model = LibraryModel()
    @State private var selected: String?
    @State private var importRequest: PackImportRequest?
    @State private var editMode = EditMode.inactive
    @State private var bulkSelected = Set<String>()
    @State private var optimizationRequest: OptimizationRequest?
    @State private var coverImages = SampleStickerImages()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func packRow(_ pack: PackManifestV1) -> some View {
        HStack(spacing: 12) {
            Group {
                if let cover = model.cover(in: pack), let image = coverImages.thumbnail(for: cover) {
                    Image(uiImage: image).resizable().scaledToFit().padding(6)
                } else { Image(systemName: "square.stack").foregroundStyle(.secondary) }
            }
            .frame(width: 52, height: 52)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.title).font(.body.weight(.semibold)).lineLimit(2, reservesSpace: true)
                Text("스티커 \(pack.stickers.count)개").font(.caption).foregroundStyle(.secondary)
                if let checked = pack.lastCheckedAt {
                    Text("최근 확인 \(checked.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                }
                if let pending = pack.pendingStickerIDs, !pending.isEmpty {
                    Text("설치 \(pack.stickers.count)/\(pack.originalCount) · 실패 \(pending.count)")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("partial.\(pack.id)")
                }
            }
            Spacer(minLength: 0)
            if pack.telegramName != nil {
                Button { importRequest = PackImportRequest(name: pack.telegramName, updating: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.glass).buttonBorderShape(.circle)
                    .frame(width: 44, height: 44)
                    .opacity(editMode == .active ? 0 : 1)
                    .allowsHitTesting(editMode != .active)
                    .accessibilityHidden(editMode == .active)
                    .accessibilityLabel("\(pack.title) 업데이트")
                    .accessibilityIdentifier("update.\(pack.id)")
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if pack.telegramName != nil {
                Button("팩 업데이트", systemImage: "arrow.clockwise") { importRequest = PackImportRequest(name: pack.telegramName, updating: true) }
                    .disabled(editMode == .active)
            }
        }
    }

    private var packEditingActions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("전체 선택") { bulkSelected = Set(model.packs.map(\.id)) }
                Button("업데이트") {
                    let links = model.packs.filter { bulkSelected.contains($0.id) }
                        .compactMap { $0.telegramName.map { "https://t.me/addstickers/" + $0 } }
                    importRequest = PackImportRequest(name: nil, updating: true, links: links)
                }
                .disabled(!model.packs.contains { bulkSelected.contains($0.id) && $0.telegramName != nil } || ImportActivity.shared.count > 0)
                .accessibilityIdentifier("updateSelectedPacks")
                Button("최적화") { optimizationRequest = OptimizationRequest(packIDs: bulkSelected) }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .accessibilityIdentifier("optimizeSelectedPacks")
            }
            .buttonStyle(.glass)
            .lineLimit(1)
        }
        .padding(12)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $bulkSelected) {
                if let message = model.message {
                    Section { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("libraryMessage") }
                }
                if model.packs.isEmpty {
                    Section {
                        ContentUnavailableView("설치한 팩이 없어요", systemImage: "square.stack",
                                               description: Text("+ 버튼에서 Telegram 스티커 팩 링크를 추가하세요."))
                    }
                }
                if !model.damagedPacks.isEmpty {
                    Section("읽을 수 없는 팩") {
                        ForEach(model.damagedPacks) { pack in
                            HStack {
                                Text(pack.id)
                                Spacer()
                                Button("삭제", role: .destructive) { Task { await model.delete(ids: [pack.id]) } }
                            }
                        }
                    }
                }
                Section("설치된 팩") {
                    ForEach(model.packs) { pack in
                        NavigationLink(value: pack.id) { packRow(pack) }
                            .tag(pack.id)
                        .accessibilityIdentifier("pack.\(pack.id)")
                        .swipeActions(edge: .trailing) {
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                Task { await model.delete(ids: [pack.id]) }
                            }
                        }
                    }
                    .onMove { source, destination in Task { await model.move(from: source, to: destination) } }
                    .moveDisabled(!model.damagedPacks.isEmpty)
                }
            }
            .onChange(of: bulkSelected) { _, ids in
                if editMode != .active, let id = ids.first { selected = id }
            }
            .onChange(of: editMode) { _, mode in
                if mode == .inactive { bulkSelected.removeAll() }
            }
            .disabled(model.isBusy)
            .environment(\.editMode, $editMode)
            // Keep the scroll geometry and Glass hosts stable across editing changes.
            .contentMargins(.bottom, 72, for: .scrollContent)
            .overlay(alignment: .bottom) {
                packEditingActions
                    .opacity(editMode == .active ? 1 : 0)
                    .offset(y: editMode == .active || reduceMotion ? 0 : 16)
                    .allowsHitTesting(editMode == .active)
                    .accessibilityHidden(editMode != .active)
            }
            .navigationTitle("내 스티커 팩")
            .toolbar {
                ToolbarItem(id: "libraryEdit", placement: .topBarLeading) {
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    } label: {
                        // A constant label width avoids relaying out the navigation bar.
                        Text(editMode == .active ? "완료" : "편집")
                            .frame(minWidth: 32)
                            .contentTransition(.interpolate)
                    }
                    .accessibilityIdentifier("editPacks")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        importRequest = PackImportRequest(name: nil, updating: false)
                    } label: { Label("팩 추가", systemImage: "plus") }
                    .accessibilityIdentifier("addPack")
                    .disabled(!model.isAvailable || model.isBusy)
                }
            }
            .overlay { if model.isBusy { ProgressView("저장 중") } }
            .refreshable { await model.refresh() }
        } detail: {
            if let pack = model.packs.first(where: { $0.id == selected }) {
                InstalledPackView(pack: pack, stickers: model.stickers(in: pack), update: {
                    importRequest = PackImportRequest(name: pack.telegramName, updating: true)
                }, retry: {
                    importRequest = PackImportRequest(name: pack.telegramName, updating: false)
                }, optimize: { ids in
                    optimizationRequest = OptimizationRequest(packIDs: [pack.id], stickerIDs: ids)
                }) {
                    await model.delete(ids: [pack.id])
                }
                .id(pack.revision)
            } else {
                ContentUnavailableView("스티커 팩을 선택하세요", systemImage: "square.grid.2x2")
            }
        }
        .sheet(item: $importRequest, onDismiss: { Task { await model.refresh() } }) { request in
            if let writer = model.writer { ImportView(writer: writer, initialPackName: request.name, updating: request.updating, initialLinks: request.links) }
        }
        .sheet(item: $optimizationRequest, onDismiss: { Task { await model.refresh() } }) { request in
            OptimizationView(request: request)
        }
        .onChange(of: ImportActivity.shared.count) { _, count in if count == 0 { Task { await model.refresh() } } }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--keyboard-ui-fixture"), let writer = model.writer {
                do { try await ImportPreviewFixture.prepareKeyboardLibrary(writer: writer) }
                catch { model.message = error.localizedDescription }
            }
            #endif
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

private struct PackImportRequest: Identifiable { let id = UUID(); let name: String?; let updating: Bool; var links: [String] = [] }

private struct SharedPNG: Identifiable { let id = UUID(); let data: Data; var type = "public.png" }

private struct InstalledPackView: View {
    @ScaledMetric(relativeTo: .subheadline) private var stickerWidth = 64
    @ScaledMetric(relativeTo: .body) private var previewHeight = 180
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pack: PackManifestV1
    let stickers: [SampleSticker]
    let update: () -> Void
    let retry: () -> Void
    let optimize: (Set<String>) -> Void
    let delete: () async -> Void
    @State private var images = SampleStickerImages()
    @State private var status = "스티커를 탭하면 크게 볼 수 있어요."
    @State private var copiedID: String?
    @State private var sharedPNG: SharedPNG?
    @State private var preview: SampleSticker?
    @State private var confirmDelete = false
    @State private var selecting = false
    @State private var selectedStickers = Set<String>()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(pack.stickers.count)개").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("installedCopyStatus")
                }
                if let pending = pack.pendingStickerIDs, !pending.isEmpty {
                    HStack {
                        Text("\(pack.originalCount)개 중 \(pack.stickers.count)개 설치 · 실패 \(pending.count)개")
                            .font(.caption).accessibilityIdentifier("installedPartialStatus")
                        Spacer()
                        Button("재시도", action: retry).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("실패한 \(pending.count)개 다시 가져오기")
                            .accessibilityIdentifier("retryMissingStickers")
                    }
                    .padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: stickerWidth, maximum: max(stickerWidth, 88)), spacing: 8)], spacing: 8) {
                    ForEach(stickers) { sticker in
                        Button {
                            if selecting {
                                if !selectedStickers.insert(sticker.id).inserted { selectedStickers.remove(sticker.id) }
                            } else { preview = sticker }
                        } label: {
                            Group {
                                if let image = images.thumbnail(for: sticker) {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                            }
                            .padding(8).frame(maxWidth: .infinity).frame(height: stickerWidth)
                            .background(copiedID == sticker.id ? Color.accentColor.opacity(0.12) : Color(uiColor: .tertiarySystemFill).opacity(0.35),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                if selecting {
                                    Image(systemName: selectedStickers.contains(sticker.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.accentColor).padding(3).background(.background, in: Circle())
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if sticker.animationURL != nil {
                                    Text("GIF").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 4).padding(.vertical, 2)
                                        .background(.background, in: Capsule()).padding(3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(sticker.animationURL == nil ? sticker.name : "\(sticker.name), 애니메이션")
                        .accessibilityHint("탭해 미리보기를 열고 복사 버튼을 선택하세요.")
                        .accessibilityIdentifier("installedCopy.\(sticker.id)")
                        .contextMenu {
                            if sticker.animationURL != nil {
                                Button("움직임 보기", systemImage: "play.rectangle") { preview = sticker }
                                    .accessibilityIdentifier("preview.\(sticker.id)")
                                Button("정적 PNG로 복사", systemImage: "photo") { copy(sticker, asPNG: true) }
                                Button("GIF 공유", systemImage: "square.and.arrow.up") { share(sticker, animated: true) }
                            }
                            Button("PNG 공유", systemImage: "square.and.arrow.up") { share(sticker, animated: false) }
                                .accessibilityIdentifier("share.\(sticker.id)")
                        }
                    }
                }
            }.padding(16)
        }
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(selecting ? "완료" : "선택") { selecting.toggle(); selectedStickers.removeAll(); preview = nil }
            if pack.telegramName != nil { Button("업데이트", systemImage: "arrow.clockwise", action: update).accessibilityIdentifier("updatePack") }
            Button("팩 삭제", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .accessibilityIdentifier("deletePack")
        }
        .confirmationDialog("이 팩을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("팩 삭제", role: .destructive) { Task { await delete(); dismiss() } }
        }
        .sheet(item: $sharedPNG) { PNGShareSheet(data: $0.data, type: $0.type).presentationDetents([.medium, .large]) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                GlassEffectContainer(spacing: 12) {
                    HStack {
                        Button("전체 선택") { selectedStickers = Set(stickers.map(\.id)) }
                        Spacer()
                        Button("선택한 \(selectedStickers.count)개 최적화") { optimize(selectedStickers) }
                            .disabled(selectedStickers.isEmpty || ImportActivity.shared.count > 0)
                    }.buttonStyle(.glass).lineLimit(1)
                }.padding(12)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let preview {
                VStack(spacing: 8) {
                    StickerLargePreview(sticker: preview)
                        .frame(maxWidth: .infinity)
                        .frame(height: min(280, previewHeight + (horizontalSizeClass == .regular ? 40 : 0)))
                        .clipped()
                        .id(preview.id)
                        .transition(.opacity)
                    if let record = pack.stickers.first(where: { preview.id == pack.id + "." + $0.id }), let quality = record.conversionQuality {
                        Text(quality.hasPrefix("용량 최적화") ? quality : "자동 품질 조절 · \(quality)").font(.caption).foregroundStyle(.secondary)
                    }
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 8) {
                            Button("최적화") { optimize([preview.id]) }.buttonStyle(.glass)
                                .disabled(ImportActivity.shared.count > 0)
                            Button("복사") { copy(preview) }.buttonStyle(.glassProminent).accessibilityIdentifier("previewCopy")
                            Button("공유", systemImage: "square.and.arrow.up") { share(preview, animated: preview.animationURL != nil) }.buttonStyle(.glass)
                            Button("닫기") { self.preview = nil }.buttonStyle(.glass).accessibilityIdentifier("previewClose")
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.subheadline)
                    }
                }
                .controlSize(.regular)
                .buttonBorderShape(.capsule)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.86), value: preview?.id)
    }

    private func copy(_ sticker: SampleSticker, asPNG: Bool = false) {
        let result = StickerCopyService().copy(sticker, isAllowed: true, asPNG: asPNG)
        if result == .copied { copiedID = sticker.id }
        status = result.message
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func share(_ sticker: SampleSticker, animated: Bool) {
        do {
            guard let url = animated ? sticker.animationURL : sticker.fileURL() else { throw LibraryError.invalidImage }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard animated ? GIFValidation.isValid(data) : PNGValidation.isValid(data) else { throw LibraryError.invalidImage }
            sharedPNG = SharedPNG(data: data, type: animated ? "com.compuserve.gif" : "public.png")
        } catch { status = "이미지를 공유할 수 없어요. 팩을 다시 확인해 주세요." }
    }
}

/// A stable PNG data representation; no temporary source file can disappear during sharing.
private final class PNGActivityItem: NSObject, UIActivityItemSource {
    let data: Data
    let type: String
    init(data: Data, type: String) { self.data = data; self.type = type }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { data }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { data }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String { type }
}

private struct PNGShareSheet: UIViewControllerRepresentable {
    let data: Data
    var type = "public.png"
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [PNGActivityItem(data: data, type: type)], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "pngShareSheet"
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
