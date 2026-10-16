import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @Environment(\.horizontalSizeClass) private var systemSizeClass
    @Environment(\.activeAppTab) private var activeTab
    @Environment(\.libraryHomeRequest) private var homeRequest
    @State private var model = LibraryModel()
    @State private var selected: String?
    @State private var importRequest: PackImportRequest?
    @State private var editMode = EditMode.inactive
    @State private var bulkSelected = Set<String>()
    @State private var optimizationRequest: OptimizationRequest?
    @State private var coverImages = StickerImages()
    @State private var confirmBulkDelete = false
    @State private var sharing = false
    @State private var sharingPack: PackManifestV1?
    @State private var deletingPack: PackManifestV1?
    @State private var editingActionsHeight: CGFloat = 0
    @State private var workBannerHeight: CGFloat = 0
    @State private var draggingPack: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Navigation selection and edit selection have different lifetimes. Completing
    // editing must not clear the currently displayed pack's sidebar highlight.
    private func listSelection(preservingDetail: Bool) -> Binding<Set<String>> {
        // A List can deliver its final deselection after EditMode has changed.
        // Route that callback using the mode of the binding it received, rather
        // than re-reading the new mode and clearing navigation by mistake.
        let editing = editMode.isEditing
        return Binding(get: {
            editing ? bulkSelected : Set(selected.map { [$0] } ?? [])
        }, set: { ids in
            // Also handle a two-finger selection gesture that has just entered
            // editing while List still holds its previous navigation binding.
            if editing || editMode.isEditing { bulkSelected = ids }
            else if let id = ids.first { selected = id }
            else if !preservingDetail { selected = nil }
        })
    }

    @ViewBuilder
    private func packNavigationRow(_ pack: PackManifestV1, wideLayout: Bool) -> some View {
        if wideLayout {
            // Keep the same row alive through editing so its selection gutter
            // slides in with the content instead of replacing the entire cell.
            Button {
                if editMode.isEditing {
                    if bulkSelected.contains(pack.id) { bulkSelected.remove(pack.id) }
                    else { bulkSelected.insert(pack.id) }
                } else {
                    selected = pack.id
                }
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: bulkSelected.contains(pack.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(bulkSelected.contains(pack.id) ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                        .frame(width: 24)
                        .offset(x: editMode.isEditing || reduceMotion ? 0 : -24)
                        .opacity(editMode.isEditing ? 1 : 0)
                        .frame(width: editMode.isEditing ? 24 : 0)
                        .clipped()
                        .padding(.trailing, editMode.isEditing ? 16 : 0)
                        .accessibilityHidden(true)
                    packRow(pack)
                }
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: editMode.isEditing)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits((editMode.isEditing ? bulkSelected.contains(pack.id) : selected == pack.id) ? .isSelected : [])
        } else {
            NavigationLink(value: pack.id) { packRow(pack) }
                .navigationLinkIndicatorVisibility(.hidden)
        }
    }

    private func packRow(_ pack: PackManifestV1) -> some View {
        HStack(spacing: 10) {
            Group {
                if let cover = model.cover(in: pack), cover.animationURL != nil {
                    StickerLargePreview(sticker: cover, pixels: 64, paused: activeTab != .library || scenePhase != .active).padding(3)
                } else if let cover = model.cover(in: pack), let image = coverImages.thumbnail(for: cover) {
                    Image(uiImage: image).resizable().scaledToFit().padding(6)
                } else { Image(systemName: "square.stack").foregroundStyle(.secondary) }
            }
            .frame(width: 44, height: 44)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                    .accessibilityLabel(pack.title)
                Text("스티커 \(pack.stickers.count)개").font(.caption).foregroundStyle(.secondary)
                if let checked = pack.lastCheckedAt {
                    Text("최근 확인 \(checked.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "ko_KR"))))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                if let pending = pack.pendingStickerIDs, !pending.isEmpty {
                    Text("설치 \(pack.stickers.count)/\(pack.originalCount) · 실패 \(pending.count)")
                        .font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("partial.\(pack.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            FixedPackChevron()
                .frame(width: 12, height: 20)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 0)
        .contextMenu {
            if !editMode.isEditing {
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
        SelectionControls.update {
            if !share && editMode == .active && sharing == share {
                editMode = .inactive
            } else {
                sharing = share
                bulkSelected = share ? Set(model.packs.map(\.id)) : []
                editMode = .active
            }
        }
    }

    private func packEditingActions() -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    let links = model.packs.filter { bulkSelected.contains($0.id) }
                        .compactMap { $0.telegramName.map { "https://t.me/addstickers/" + $0 } }
                    importRequest = PackImportRequest(name: nil, updating: true, links: links)
                } label: { actionLabel("업데이트 확인", icon: "arrow.clockwise") }
                .disabled(!model.packs.contains { bulkSelected.contains($0.id) && $0.telegramName != nil } || ImportActivity.shared.count > 0)
                .tint(.blue).accessibilityIdentifier("updateSelectedPacks")
                Button { optimizationRequest = OptimizationRequest(packIDs: bulkSelected) } label: { actionLabel("용량 최적화", icon: "slider.horizontal.3") }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .tint(.indigo).accessibilityIdentifier("optimizeSelectedPacks")
                Button(role: .destructive) { confirmBulkDelete = true } label: { actionLabel("삭제", icon: "trash") }
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
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 24, height: 24)
            .contentShape(Capsule())
    }

    private func addPack() {
        if ImportActivity.shared.current?.busy == true { ImportActivity.shared.presentCurrent() }
        else if OptimizationCenter.shared.current?.running == true { OptimizationCenter.shared.presentCurrent() }
        else { importRequest = PackImportRequest(name: nil, updating: false) }
    }

    var body: some View {
        GeometryReader { geometry in
        let wideLayout = geometry.size.width >= 600 && (UIDevice.current.userInterfaceIdiom == .pad || geometry.size.width > geometry.size.height)
        let sidebarMaximum = geometry.size.width / 3
        let sidebarMinimum = min(300, sidebarMaximum)
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            List(selection: listSelection(preservingDetail: wideLayout)) {
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
                Section {
                    ForEach(model.packs) { pack in
                        packNavigationRow(pack, wideLayout: wideLayout)
                                .contentShape(Rectangle())
                                .onDrag {
                                    guard editMode.isEditing, !model.isBusy, model.damagedPacks.isEmpty,
                                          ImportActivity.shared.count == 0 else { return NSItemProvider() }
                                    draggingPack = pack.id
                                    return NSItemProvider(object: pack.id as NSString)
                                }
                        .tag(pack.id)
                        .listRowInsets(EdgeInsets(top: wideLayout ? 20 : 16, leading: wideLayout ? 20 : 16, bottom: wideLayout ? 20 : 16, trailing: wideLayout ? 10 : 16))
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            guard editMode.isEditing, !model.isBusy, ImportActivity.shared.count == 0,
                                  model.damagedPacks.isEmpty,
                                  let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
                            provider.loadObject(ofClass: NSString.self) { object, _ in
                                guard let sourceID = object as? String else { return }
                                Task { @MainActor in
                                    guard editMode.isEditing,
                                          let source = model.packs.firstIndex(where: { $0.id == sourceID }),
                                          let target = model.packs.firstIndex(where: { $0.id == pack.id }), source != target else { return }
                                    draggingPack = nil
                                    await model.move(from: IndexSet(integer: source), to: target > source ? target + 1 : target)
                                }
                            }
                            return true
                        }
                        .accessibilityIdentifier("pack.\(pack.id)")
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button("업데이트 확인", systemImage: "arrow.clockwise") { updatePack(pack) }
                                .labelStyle(.iconOnly).tint(.blue).disabled(pack.telegramName == nil || ImportActivity.shared.count > 0)
                            Button("용량 최적화", systemImage: "slider.horizontal.3") { optimizationRequest = OptimizationRequest(packIDs: [pack.id]) }
                                .labelStyle(.iconOnly).tint(.indigo).disabled(ImportActivity.shared.count > 0)
                            Button("공유", systemImage: "square.and.arrow.up") { sharingPack = pack }
                                .labelStyle(.iconOnly).tint(.teal).disabled(pack.telegramName == nil)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                Task { await model.delete(ids: [pack.id]) }
                            }.labelStyle(.iconOnly)
                        }
                    }

                }
                .listRowBackground(wideLayout ? Color.clear : nil)
                .listSectionMargins(.leading, wideLayout ? 0 : 20)
                .listSectionMargins(.trailing, wideLayout ? 0 : 20)
            }
            .modifier(LibraryListStyle(wideLayout: wideLayout))
            .scrollContentBackground(wideLayout ? .hidden : .automatic)
            .background(wideLayout ? Color(uiColor: .systemBackground) : Color.clear)
            .environment(\.editMode, wideLayout ? .constant(.inactive) : $editMode)
            .onChange(of: editMode) { _, mode in
                if mode == .inactive { bulkSelected.removeAll() }
            }
            .disabled(model.isBusy)
            .contentMargins(.bottom, workBannerHeight + editingActionsHeight, for: .scrollContent)
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
                        } else { packEditingActions() }
                    }
                    .frame(height: 68)
                    .opacity(editMode.isEditing ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: editMode.isEditing)

                    .allowsHitTesting(editMode.isEditing)
                    .accessibilityHidden(!editMode.isEditing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { editingActionsHeight = $0 }
                    CurrentWorkBanner()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { workBannerHeight = $0 }
                }
            }
            .navigationTitle(wideLayout ? "" : "내 스티커 팩")
            .toolbar {
                SelectionControls(id: "librarySelection", active: editMode == .active, title: "편집",
                                      toggle: {
                                          if editMode.isEditing { SelectionControls.update { resetSelection() } }
                                          else { toggleSelection(sharing: false) }
                                      })
                ToolbarItem(placement: .topBarTrailing) {
                    Button { toggleSelection(sharing: true) } label: { Label("공유할 팩 선택", systemImage: "square.and.arrow.up") }
                        .labelStyle(.iconOnly)
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
            .navigationSplitViewColumnWidth(min: sidebarMinimum, ideal: sidebarMinimum, max: sidebarMaximum)
            .overlay(alignment: .trailing) {
                if wideLayout {
                    Rectangle().fill(Color(uiColor: .separator))
                        .frame(width: 1 / max(1, displayScale))
                        .ignoresSafeArea(edges: .vertical)
                        .allowsHitTesting(false)
                }
            }
        } detail: {
            detailContent(landscape: geometry.size.width > geometry.size.height)
        }
        .background {
            LibraryRotationObserver {
                columnVisibility = .all
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.horizontalSizeClass, wideLayout ? .regular : systemSizeClass)
        .onChange(of: model.packs.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected) { self.selected = nil }
            bulkSelected.formIntersection(ids)
        }
        .onChange(of: wideLayout, initial: true) { _, wide in
            if wide {
                columnVisibility = .all
            } else {
                compactColumn = selected == nil ? .sidebar : .detail
                columnVisibility = .automatic
            }
        }
        .onChange(of: PackLinkInbox.shared.received?.id) { _, received in if received == nil { Task { await model.refresh() } } }
        .sheet(item: $sharingPack) { pack in PackTextShareSheet(text: PackLinkList.links(for: [pack]).joined(separator: "\n")) }
        .sheet(item: $importRequest, onDismiss: { Task { await model.refresh() } }) { request in
            if let writer = model.writer { ImportView(writer: writer, initialPackName: request.name, updating: request.updating, initialLinks: request.links, initialPackTitle: request.title) }
        }
        .sheet(item: $optimizationRequest, onDismiss: { Task { await model.refresh() } }) { request in
            OptimizationView(request: request)
        }
        .onChange(of: homeRequest) { _, _ in
            resetSelection()
            selected = nil
            compactColumn = .sidebar
            columnVisibility = .all
        }
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
    }
    @ViewBuilder
    private func detailContent(landscape: Bool) -> some View {
            Group {
            if let pack = model.packs.first(where: { $0.id == selected }) {
                InstalledPackView(landscape: landscape, pack: pack, stickers: model.stickers(in: pack), update: {
                    importRequest = PackImportRequest(name: pack.telegramName, updating: true, title: pack.title)
                }, retry: {
                    importRequest = PackImportRequest(name: pack.telegramName, updating: false)
                }, optimize: { ids in
                    optimizationRequest = OptimizationRequest(packIDs: [pack.id], stickerIDs: ids.isEmpty ? nil : ids)
                }) {
                    await model.delete(ids: [pack.id])
                }
            } else {
                ContentUnavailableView("스티커 팩을 선택하세요", systemImage: "square.grid.2x2")

            }
            }

    }

    private func resetSelection() {
        editMode = .inactive
        sharing = false
        bulkSelected.removeAll()
        confirmBulkDelete = false
        deletingPack = nil
        draggingPack = nil
    }

}

private struct LibraryListStyle: ViewModifier {
    let wideLayout: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if wideLayout { content.listStyle(.plain) }
        else { content.listStyle(.insetGrouped) }
    }
}
