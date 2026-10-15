import SwiftUI
import UniformTypeIdentifiers
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
        guard let writer, !isBusy, !ids.isEmpty else { return }
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
    @State private var bottomActionsHeight: CGFloat = 72
    @State private var confirmBulkDelete = false
    @State private var sharing = false
    @State private var sharingPack: PackManifestV1?
    @State private var deletingPack: PackManifestV1?
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
                        .font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("partial.\(pack.id)")
                }
            }
            Spacer(minLength: 0)

        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("업데이트 확인", systemImage: "arrow.clockwise") { updatePack(pack) }
                .disabled(pack.telegramName == nil || ImportActivity.shared.count > 0)
            Button("용량 최적화", systemImage: "slider.horizontal.3") { optimizationRequest = OptimizationRequest(packIDs: [pack.id]) }
                .disabled(ImportActivity.shared.count > 0)
            ShareLink(item: PackLinkList.links(for: [pack]).joined(separator: "\n")) {
                Label("Sticker Pack 링크 공유", systemImage: "square.and.arrow.up")
            }.disabled(PackLinkList.links(for: [pack]).isEmpty)
            Button("삭제", systemImage: "trash", role: .destructive) { deletingPack = pack }
                .disabled(ImportActivity.shared.count > 0)
        }
        .confirmationDialog("이 팩을 삭제할까요?", isPresented: Binding(
            get: { deletingPack?.id == pack.id }, set: { if !$0 { deletingPack = nil } }
        ), titleVisibility: .visible) {
            Button("팩 삭제", role: .destructive) {
                deletingPack = nil
                Task { await model.delete(ids: [pack.id]) }
            }
        }
    }

    private func updatePack(_ pack: PackManifestV1) {
        importRequest = PackImportRequest(name: pack.telegramName, updating: true, title: pack.title)
    }

    private func toggleSelection(sharing share: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.82)) {
            if editMode == .active && sharing == share {
                editMode = .inactive; sharing = false
            } else {
                sharing = share
                bulkSelected = share ? Set(model.packs.map(\.id)) : []
                editMode = .active
            }
        }
    }

    private var packEditingActions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 8) {
                Button("업데이트 확인") {
                    let links = model.packs.filter { bulkSelected.contains($0.id) }
                        .compactMap { $0.telegramName.map { "https://t.me/addstickers/" + $0 } }
                    importRequest = PackImportRequest(name: nil, updating: true, links: links)
                }
                .disabled(!model.packs.contains { bulkSelected.contains($0.id) && $0.telegramName != nil } || ImportActivity.shared.count > 0)
                .accessibilityIdentifier("updateSelectedPacks")
                Button("용량 최적화") { optimizationRequest = OptimizationRequest(packIDs: bulkSelected) }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .accessibilityIdentifier("optimizeSelectedPacks")
                Button("삭제", role: .destructive) { confirmBulkDelete = true }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .accessibilityIdentifier("deleteSelectedPacks")
                    .confirmationDialog("선택한 \(bulkSelected.count)개 팩을 삭제할까요?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
                        Button("선택한 팩 삭제", role: .destructive) {
                            let ids = Array(bulkSelected)
                            bulkSelected.removeAll()
                            Task { await model.delete(ids: ids) }
                        }
                    }
            }
            .font(.subheadline)
            .buttonStyle(.glass)
            .controlSize(.large)
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
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button("업데이트 확인", systemImage: "arrow.clockwise") { updatePack(pack) }
                                .tint(.blue).disabled(pack.telegramName == nil || ImportActivity.shared.count > 0)
                            Button("용량 최적화", systemImage: "slider.horizontal.3") { optimizationRequest = OptimizationRequest(packIDs: [pack.id]) }
                                .tint(.indigo).disabled(ImportActivity.shared.count > 0)
                            Button("공유", systemImage: "square.and.arrow.up") { sharingPack = pack }
                                .tint(.teal).disabled(pack.telegramName == nil)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                Task { await model.delete(ids: [pack.id]) }
                            }
                        }
                    }
                    .onMove { source, destination in Task { await model.move(from: source, to: destination) } }
                    .moveDisabled(!model.damagedPacks.isEmpty || ImportActivity.shared.count > 0)
                }
            }
            .onChange(of: bulkSelected) { _, ids in
                if editMode != .active, let id = ids.first { selected = id }
            }
            .onChange(of: editMode) { _, mode in
                if mode == .inactive { bulkSelected.removeAll(); sharing = false }
            }
            .disabled(model.isBusy)
            .environment(\.editMode, $editMode)
            // Keep the scroll geometry and Glass hosts stable across editing changes.
            .contentMargins(.bottom, bottomActionsHeight, for: .scrollContent)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Group {
                        if sharing {
                            let links = PackLinkList.links(for: model.packs.filter { bulkSelected.contains($0.id) })
                            ShareLink(item: StickerLinkFile(text: links.joined(separator: "\n")), preview: SharePreview("스티커 팩 링크 목록")) {
                                Label("선택한 팩 공유", systemImage: "square.and.arrow.up")
                            }
                            .disabled(links.isEmpty)
                            .buttonStyle(.glassProminent).controlSize(.large).padding(12)
                        } else { packEditingActions }
                    }
                        .opacity(editMode == .active ? 1 : 0)
                        .offset(y: editMode == .active || reduceMotion ? 0 : 16)
                        .allowsHitTesting(editMode == .active)
                        .accessibilityHidden(editMode != .active)
                    CurrentWorkBanner()
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomActionsHeight = $0 }
            }
            .navigationTitle("내 스티커 팩")
            .toolbar {
                ToolbarItem(id: "libraryEdit", placement: .topBarLeading) {
                    Button { toggleSelection(sharing: editMode == .active ? sharing : false) } label: {
                        Text(editMode == .active ? "완료" : "편집")
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                    .accessibilityIdentifier("editPacks")
                }
                if editMode == .active {
                    ToolbarSpacer(.fixed, placement: .topBarLeading)
                    ToolbarItem(id: "librarySelectAll", placement: .topBarLeading) {
                        Button {
                            let all = Set(model.packs.map(\.id))
                            bulkSelected = bulkSelected == all ? [] : all
                        } label: {
                            Text(bulkSelected == Set(model.packs.map(\.id)) && !model.packs.isEmpty ? "전체 해제" : "전체 선택")
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        }
                        .disabled(model.packs.isEmpty).accessibilityIdentifier("selectAllPacks")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { toggleSelection(sharing: true) } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("공유할 팩 선택").accessibilityIdentifier("selectPacksToShare")
                        .disabled(model.packs.isEmpty || model.isBusy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if ImportActivity.shared.current?.busy == true {
                            ImportActivity.shared.presentCurrent()
                        } else if OptimizationCenter.shared.current?.running == true {
                            OptimizationCenter.shared.presentCurrent()
                        } else {
                            importRequest = PackImportRequest(name: nil, updating: false)
                        }
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
                    importRequest = PackImportRequest(name: pack.telegramName, updating: true, title: pack.title)
                }, retry: {
                    importRequest = PackImportRequest(name: pack.telegramName, updating: false)
                }, optimize: { ids in
                    optimizationRequest = OptimizationRequest(packIDs: [pack.id], stickerIDs: ids.isEmpty ? nil : ids)
                }) {
                    await model.delete(ids: [pack.id])
                }
                .id(pack.revision)
            } else {
                ContentUnavailableView("스티커 팩을 선택하세요", systemImage: "square.grid.2x2")
            }
        }
        .onChange(of: PackLinkInbox.shared.received?.id) { _, received in if received == nil { Task { await model.refresh() } } }
        .sheet(item: $sharingPack) { pack in PackLinksShareView(links: PackLinkList.links(for: [pack])) }
        .sheet(item: $importRequest, onDismiss: { Task { await model.refresh() } }) { request in
            if let writer = model.writer { ImportView(writer: writer, initialPackName: request.name, updating: request.updating, initialLinks: request.links, initialPackTitle: request.title) }
        }
        .sheet(item: $optimizationRequest, onDismiss: { Task { await model.refresh() } }) { request in
            OptimizationView(request: request)
        }
        .onChange(of: ImportActivity.shared.libraryChangeID) { _, _ in Task { await model.refresh() } }
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

private struct PackImportRequest: Identifiable { let id = UUID(); let name: String?; let updating: Bool; var links: [String] = []; var title: String? = nil }

private struct SharedPNG: Identifiable { let id = UUID(); let data: Data; var type = "public.png" }

private struct InstalledPackView: View {
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
    @State private var permissionWarning = false
    @State private var confirmDelete = false
    @State private var selecting = false
    @State private var selectedStickers = Set<String>()
    @State private var columnCount = 4
    @State private var pinchStartColumns: Int?
    @State private var storageBytes: Int64?

    private var gridZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let startingColumns = pinchStartColumns ?? columnCount
                pinchStartColumns = startingColumns
                let columns = min(10, max(2, Int((Double(startingColumns) / value.magnification).rounded())))
                guard columns != columnCount else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)) {
                    columnCount = columns
                }
            }
            .onEnded { _ in pinchStartColumns = nil }
    }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
        let cellWidth = max(1, (geometry.size.width - 24 - CGFloat(columnCount - 1) * 4) / CGFloat(columnCount))
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(pack.stickers.count)개").font(.subheadline.weight(.semibold))
                    if let storageBytes {
                        Text(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("팩 저장 용량 \(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))")
                    }
                    Spacer()
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("installedCopyStatus")
                }
                if let pending = pack.pendingStickerIDs, !pending.isEmpty {
                    HStack {
                        Text("\(pack.originalCount)개 중 \(pack.stickers.count)개 설치 · 실패 \(pending.count)개")
                            .font(.caption).foregroundStyle(.red).accessibilityIdentifier("installedPartialStatus")
                        Spacer()
                        Button("재시도", action: retry).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("실패한 \(pending.count)개 다시 가져오기")
                            .accessibilityIdentifier("retryMissingStickers")
                    }
                    .padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount), spacing: 4) {
                    ForEach(stickers) { sticker in
                        Button {
                            if selecting {
                                if !selectedStickers.insert(sticker.id).inserted { selectedStickers.remove(sticker.id) }
                            } else { preview = preview?.id == sticker.id ? nil : sticker }
                        } label: {
                            Group {
                                if sticker.animationURL != nil {
                                    StickerLargePreview(sticker: sticker)
                                        .accessibilityHidden(true)
                                        .allowsHitTesting(false)
                                } else if let image = images.thumbnail(for: sticker) {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                            }
                            .padding(3).frame(maxWidth: .infinity).frame(height: cellWidth)
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
                        .accessibilityHint("다시 탭하면 미리보기를 닫아요. 길게 누르면 복사와 공유를 할 수 있어요.")
                        .accessibilityIdentifier("installedCopy.\(sticker.id)")
                        .contextMenu {
                            Button("복사", systemImage: "doc.on.doc") { copy(sticker) }
                            Button("공유", systemImage: "square.and.arrow.up") { share(sticker, animated: sticker.animationURL != nil) }
                        }
                    }
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .simultaneousGesture(gridZoom)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(id: "stickerSelection", placement: .topBarLeading) {
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) {
                        selecting.toggle(); selectedStickers.removeAll(); preview = nil
                    }
                } label: {
                    Text(selecting ? "완료" : "선택").lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
            }
            if selecting {
                ToolbarSpacer(.fixed, placement: .topBarLeading)
                ToolbarItem(id: "stickerSelectAll", placement: .topBarLeading) {
                    Button {
                        let all = Set(stickers.map(\.id))
                        selectedStickers = selectedStickers == all ? [] : all
                    } label: {
                        Text(!stickers.isEmpty && selectedStickers == Set(stickers.map(\.id)) ? "전체 해제" : "전체 선택")
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }.disabled(stickers.isEmpty)
                }
            }
            if !selecting {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: PackLinkList.links(for: [pack]).joined(separator: "\n")) {
                        Label("Sticker Pack 링크 공유", systemImage: "square.and.arrow.up")
                    }
                    .disabled(PackLinkList.links(for: [pack]).isEmpty)
                    .labelStyle(.iconOnly).accessibilityIdentifier("sharePackLink")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if pack.telegramName != nil {
                        Button("업데이트 확인", systemImage: "arrow.clockwise", action: update)
                            .disabled(selecting || ImportActivity.shared.count > 0)
                            .accessibilityIdentifier("updatePack")
                    }
                    Button(selecting ? "선택한 \(selectedStickers.count)개 용량 최적화" : "용량 최적화", systemImage: "slider.horizontal.3") {
                        optimize(selecting ? selectedStickers : [])
                    }
                    .disabled(ImportActivity.shared.count > 0 || (selecting && selectedStickers.isEmpty))
                    .accessibilityIdentifier("optimizePack")
                } label: { Label("옵션", systemImage: "ellipsis") }
                    .labelStyle(.iconOnly).accessibilityIdentifier("packOptions")
            }
            if !selecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("팩 삭제", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("deletePack")
                }
            }
        }
        .alert("키보드 전체 접근을 확인해 주세요", isPresented: $permissionWarning) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("확인", role: .cancel) {}
        } message: { Text("앱에서 복사는 가능하지만, 키보드에서 복사하려면 전체 접근이 필요해요. 설정 → StickerBridge → 키보드에서 허용하고 키보드를 한 번 열어 주세요.") }
        .confirmationDialog("이 팩을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("팩 삭제", role: .destructive) { Task { await delete(); dismiss() } }
        }
        .sheet(item: $sharedPNG) { PNGShareSheet(data: $0.data, type: $0.type).presentationDetents([.medium, .large]) }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(pack.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .accessibilityAddTraits(.isHeader)
                    .background(Color(uiColor: .systemBackground))
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
                    }
                    .onTapGesture { self.preview = nil }
                    .contextMenu {
                        Button("복사", systemImage: "doc.on.doc") { copy(preview) }
                        Button("공유", systemImage: "square.and.arrow.up") { share(preview, animated: preview.animationURL != nil) }
                    }
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.86), value: preview?.id)
        .task(id: pack.revision) {
            let pack = pack
            let bytes = await Task.detached(priority: .utility) { () -> Int64? in
                guard let reader = try? LibraryReader.shared() else { return nil }
                var paths = Set(pack.stickers.flatMap { record in
                    [record.pngPath, record.thumbnailPath] + [record.animationPath, record.playbackPath].compactMap { $0 }
                })
                paths.insert("packs/\(pack.id)/\(pack.revision)/manifest.json")
                var checkedDirectories = Set<String>()
                var total: Int64 = 0
                for path in paths {
                    guard let url = try? reader.file(path, checkedDirectories: &checkedDirectories),
                          let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true, let size = values.fileSize else { continue }
                    total += Int64(size)
                }
                return total
            }.value
            guard !Task.isCancelled else { return }
            storageBytes = bytes
        }
    }

    private func copy(_ sticker: SampleSticker, asPNG: Bool = false) {
        permissionWarning = KeyboardAccessReceipt.lastAllowed == nil
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
