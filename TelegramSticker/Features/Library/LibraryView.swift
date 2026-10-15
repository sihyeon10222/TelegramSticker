import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.activeAppTab) private var activeTab
    @State private var model = LibraryModel()
    @State private var selected: String?
    @State private var importRequest: PackImportRequest?
    @State private var editMode = EditMode.inactive
    @State private var bulkSelected = Set<String>()
    @State private var optimizationRequest: OptimizationRequest?
    @State private var coverImages = StickerImages()
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
                .tint(.blue).accessibilityIdentifier("updateSelectedPacks")
                Button("용량 최적화") { optimizationRequest = OptimizationRequest(packIDs: bulkSelected) }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .tint(.indigo).accessibilityIdentifier("optimizeSelectedPacks")
                Button("삭제", role: .destructive) { confirmBulkDelete = true }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .tint(.red).accessibilityIdentifier("deleteSelectedPacks")
                    .confirmationDialog("선택한 \(bulkSelected.count)개 팩을 삭제할까요?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
                        Button("선택한 팩 삭제", role: .destructive) {
                            let ids = Array(bulkSelected)
                            bulkSelected.removeAll()
                            Task { await model.delete(ids: ids) }
                        }
                    }
            }
            .font(.subheadline)
            .buttonStyle(.glassProminent)
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
        .onDisappear { resetSelection() }
        .onChange(of: activeTab) { _, tab in
            if tab != .library { resetSelection() }
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
    private func resetSelection() {
        editMode = .inactive
        sharing = false
        bulkSelected.removeAll()
        confirmBulkDelete = false
        deletingPack = nil
    }

}
