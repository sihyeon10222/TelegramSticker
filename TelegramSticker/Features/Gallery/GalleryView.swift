import SwiftUI

/// Developer-curated links only. Sticker files remain on Telegram until a user installs a pack.
nonisolated struct GalleryRecommendation: Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    var link: String { "https://t.me/addstickers/" + id }
}

nonisolated enum GalleryCatalog {
    // Edit this list to publish a different selection in the next app version.
    static let packs: [GalleryRecommendation] = [
        .init(id: "kakaofriendsbasicminiface1dog", title: "kakaofriendsbasicminiface1dog", symbol: "face.smiling"),
        .init(id: "mellborov", title: "mellborov", symbol: "sparkles"),
        .init(id: "inbumtikon", title: "inbumtikon", symbol: "face.smiling"),
        .init(id: "pepepackbyrick", title: "pepepackbyrick", symbol: "face.smiling"),
        .init(id: "peepo_pepe", title: "peepo_pepe", symbol: "face.smiling"),
        .init(id: "apupack0", title: "apupack0", symbol: "face.smiling"),
        .init(id: "peepohd", title: "peepohd", symbol: "face.smiling"),
        .init(id: "apuapustajahd", title: "apuapustajahd", symbol: "face.smiling"),
        .init(id: "dccon_real_1762389696919_by_tg_sticker_factory_bot", title: "DCcon", symbol: "star"),
        .init(id: "pepetopanim", title: "pepetopanim", symbol: "face.smiling"),
        .init(id: "honkaunderspeed", title: "honkaunderspeed", symbol: "face.smiling")
    ]
}

private struct GalleryInstallation: Identifiable {
    let id = UUID()
    let links: [String]
}

struct GalleryView: View {
    @Bindable private var catalog = GalleryCatalogStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var galleryVisible = false
    @State private var selected = Set<String>()
    @State private var selectionFrames: [String: CGRect] = [:]
    @State private var suppressTapUntil = Date.distantPast
    @State private var selectionGeneration = 0
    private var selectableIDs: [String] { catalog.packs.filter { !installed.contains($0.id.lowercased()) }.map(\.id) }
    @State private var installed = Set<String>()
    @State private var client: WorkerClient?
    @State private var installation: GalleryInstallation?
    @State private var error: String?
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 320), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("추천 스티커 팩").font(.title2.bold())
                        Text("마음에 드는 팩을 선택하면 링크 입력 없이 바로 설치할 수 있어요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let notice = catalog.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if catalog.packs.isEmpty { ContentUnavailableView("추천 팩이 없어요", systemImage: "square.grid.2x2") }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(catalog.packs) { entry in
                            GalleryPackCard(entry: entry, client: client, selected: selected.contains(entry.id),
                                            installed: installed.contains(entry.id.lowercased()), galleryVisible: galleryVisible && installation == nil && ImportActivity.shared.presentedImport == nil && OptimizationCenter.shared.presented == nil) {
                                guard Date() >= suppressTapUntil else { return }
                                if !selected.insert(entry.id).inserted { selected.remove(entry.id) }
                            }
                            .background {
                                GeometryReader { cell in
                                    Color.clear.preference(key: StickerSelectionFrames.self,
                                        value: installed.contains(entry.id.lowercased()) ? [:] : [entry.id: cell.frame(in: .named("gallerySelectionGrid"))])
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "gallerySelectionGrid")
                    .onPreferenceChange(StickerSelectionFrames.self) { selectionFrames = $0 }
                    .background {
                        StickerDragSelection(active: galleryVisible && installation == nil && ImportActivity.shared.presentedImport == nil && OptimizationCenter.shared.presented == nil,
                            generation: selectionGeneration, frames: selectionFrames, orderedIDs: selectableIDs, selection: $selected,
                            began: { suppressTapUntil = .distantFuture },
                            ended: { suppressTapUntil = Date().addingTimeInterval(0.35) })
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in selectionGeneration += 1 }
                }.padding([.top, .horizontal], 16).padding(.bottom, 12)
                    .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
            }
            .refreshable { if let client { await catalog.refresh(client: client, force: true) } }
            .navigationTitle("갤러리")
            .toolbar {
                Button(selected.isEmpty ? "전체 선택" : "선택 해제") {
                    if selected.isEmpty { selected = Set(selectableIDs) } else { selected.removeAll() }
                }.disabled(selected.isEmpty && selectableIDs.isEmpty)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !selected.isEmpty {
                    Button {
                            guard ImportActivity.shared.count == 0, LibraryWriter.shared != nil else { return }
                            let links = catalog.packs.filter { selected.contains($0.id) && !installed.contains($0.id.lowercased()) }.map(\.link)
                            guard !links.isEmpty else { return }
                            installation = GalleryInstallation(links: links)
                            selected.removeAll()
                        } label: {
                            Label("선택한 \(selected.count)개 팩 설치", systemImage: "arrow.down.circle")

                                .frame(maxWidth: .infinity)
                        }
                        .appGlassButton(prominent: true).controlSize(.large)
                        .disabled(selected.isEmpty || ImportActivity.shared.count > 0 || LibraryWriter.shared == nil)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    CurrentWorkBanner()
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected.isEmpty)
            }
            .sheet(item: $installation, onDismiss: { Task { await refreshInstalled() } }) { request in
                if let writer = LibraryWriter.shared { ImportView(writer: writer, initialLinks: request.links) }
            }
            .alert("갤러리", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(error ?? "") }
            .task(id: galleryVisible && scenePhase == .active) {
                guard galleryVisible, scenePhase == .active else { return }
                await catalog.restore()
                guard !Task.isCancelled else { return }
                do {
                    if client == nil, let config = try ImportSettings.load() { client = WorkerClient(configuration: config) }
                } catch { self.error = error.localizedDescription }
                await refreshInstalled()
                if let client { await catalog.refresh(client: client) }
            }
            .onAppear { galleryVisible = true }
            .onDisappear { galleryVisible = false; GalleryPreviewState.shared.cancelLoading() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { GalleryPreviewState.shared.cancelLoading() }
            }
            .onChange(of: catalog.packs.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .onChange(of: ImportActivity.shared.libraryChangeID) { _, _ in Task { await refreshInstalled() } }
        }
    }

    private func refreshInstalled() async {
        let names = await Task.detached { () -> Set<String> in
            guard let reader = try? LibraryReader.shared(), let snapshot = try? reader.snapshot(resolvingFiles: false) else { return [] }
            return Set(snapshot.packs.filter { ($0.pendingStickerIDs ?? []).isEmpty }
                .compactMap { $0.telegramName?.lowercased() })
        }.value
        installed = names
        selected = Set(selected.filter { !names.contains($0.lowercased()) })
    }
}

private struct GalleryPackCard: View {
    let entry: GalleryRecommendation
    let client: WorkerClient?
    let selected: Bool
    let installed: Bool
    let galleryVisible: Bool
    let select: () -> Void
    @State private var cardVisible = false
    private var pack: RemotePack? { previewCache.metadata[entry.id] }
    @State private var previewUnavailable = false
    @Bindable private var previewCache = GalleryPreviewState.shared

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let pack, let client, !pack.stickers.isEmpty {
                        ForEach(Array(pack.stickers.prefix(3))) { sticker in
                            GalleryStickerPreview(pack: pack.name, sticker: sticker, client: client, visible: cardVisible && galleryVisible)
                        }
                    } else {
                        Image(systemName: entry.symbol).font(.system(size: 32)).foregroundStyle(.tint)
                            .frame(maxWidth: .infinity).frame(height: 88)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
                HStack(alignment: .top, spacing: 8) {
                    Text(pack?.title ?? entry.title).font(.headline).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: installed ? "checkmark.seal.fill" : selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(installed ? Color.green : selected ? Color.accentColor : Color.secondary)

                }
                if installed {
                    Text("설치됨").font(.caption).foregroundStyle(.secondary)
                } else if let pack {
                    Text("\(pack.stickers.count)개 스티커").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(previewUnavailable ? "미리보기 없음 · 링크로 설치 가능" : "Telegram 공개 팩")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.09) : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5) }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(installed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((pack?.title ?? entry.title) + (installed ? ", 설치됨" : selected ? ", 선택됨" : ", 선택 안 됨"))
        .onAppear { cardVisible = true }
        .onDisappear { cardVisible = false }
        .task(id: "\(cardVisible && galleryVisible)-\(client != nil)-\(previewCache.generation)") {
            guard cardVisible, galleryVisible, !previewCache.maintaining else { return }
            await previewCache.restore(name: entry.id)
            guard !Task.isCancelled, let client else { return }
            // Publish durable metadata before waiting for a freshness check.
            if let cached = await GalleryMetadataStore.shared.cached(name: entry.id) {
                previewCache.metadata[entry.id] = cached; previewUnavailable = false
            }
            do {
                let refreshed = try await GalleryMetadataStore.shared.pack(name: entry.id, client: client)
                try Task.checkCancellation()
                previewCache.metadata[entry.id] = refreshed; previewUnavailable = false
            }
            catch is CancellationError { return }
            catch { previewUnavailable = pack == nil }
        }
    }
}
