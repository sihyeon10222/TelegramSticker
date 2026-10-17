import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @FocusState private var commandFocus: Bool
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
    @State private var sidebarScrolling = false
    @State private var confirmBulkDelete = false
    @State private var sharing = false
    @State private var sharingPack: PackManifestV1?
    @State private var deletingPendingPack: String?
    @State private var deletingPack: PackManifestV1?
    @State private var sidebarScrolledUnderToolbar = false
    @State private var editingActionsHeight: CGFloat = 0
    @State private var workBannerHeight: CGFloat = 0
    @State private var draggingPack: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Keep bulk selection independent of detail navigation so entering edit
    // mode cannot replace the packs preselected by the share action.
    private var listSelection: Binding<Set<String>>? {
        #if targetEnvironment(macCatalyst)
        // Catalyst uses explicit toggles so an unmodified click adds to the
        // selection instead of replacing it with the native desktop selection.
        return nil
        #else
        return Binding(get: { bulkSelected }, set: { ids in
            // List can report a normal row tap as selection while inactive.
            // Only accept bulk selection after an explicit edit action or the
            // system multi-selection gesture has entered editing (.transient).
            guard editMode.isEditing else { return }
            bulkSelected = ids
            if editMode == .transient && !ids.isEmpty {
                sharing = false
                editMode = .active
            }
        })
        #endif
    }

    private func packNavigationRow(_ pack: PackManifestV1) -> some View {
        // Preserve row identity while List animates its native selection control.
        Button {
            #if targetEnvironment(macCatalyst)
            commandFocus = true
            if editMode.isEditing {
                if !bulkSelected.insert(pack.id).inserted { bulkSelected.remove(pack.id) }
                return
            }
            #else
            guard !editMode.isEditing else { return }
            #endif
            selected = pack.id
            compactColumn = .detail
        } label: {
            HStack(spacing: 12) {
                #if targetEnvironment(macCatalyst)
                if editMode.isEditing {
                    Image(systemName: bulkSelected.contains(pack.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(bulkSelected.contains(pack.id) ? Color.accentColor : Color.secondary)
                        .font(.title3)
                        .accessibilityHidden(true)
                }
                #endif
                packRow(pack)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Split-view columns can resolve semantic backgrounds at an elevated level.
    // Resolve both orientations at the base level while retaining dark mode.
    private func listColor(_ color: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            color.resolvedColor(with: traits.modifyingTraits { $0.userInterfaceLevel = .base })
        })
    }

    private func packRow(_ pack: PackManifestV1) -> some View {
        HStack(spacing: 10) {
            Group {
                if let cover = model.cover(in: pack) {
                    StickerLargePreview(sticker: cover, pixels: 64,
                        paused: sidebarScrolling || activeTab != .library || scenePhase != .active || reduceMotion)
                        .padding(cover.animationURL == nil ? 6 : 3)
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
        .confirmationDialog(LibrarySyncService.shared.enabled && LibraryChangeJournal.cloudKitConfigured ? "모든 기기에서 이 팩을 삭제할까요?" : "이 팩을 삭제할까요?", isPresented: Binding(
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

    @ViewBuilder private func packEditingActions() -> some View {
        #if targetEnvironment(macCatalyst)
        packEditingButtons
            .controlSize(.regular)
            .padding(.horizontal, 8).padding(.vertical, 4)
        #else
        GlassEffectContainer(spacing: 12) { packEditingButtons.controlSize(.small) }
            .padding(.horizontal, 8).padding(.vertical, 4)
        #endif
    }

    private var packEditingButtons: some View {
            HStack(spacing: 8) {
                Button {
                    let links = model.packs.filter { bulkSelected.contains($0.id) }
                        .compactMap { $0.telegramName.map { "https://t.me/addstickers/" + $0 } }
                    importRequest = PackImportRequest(name: nil, updating: true, links: links)
                } label: { actionLabel("업데이트 확인", icon: "arrow.clockwise") }
                .disabled(!model.packs.contains { bulkSelected.contains($0.id) && $0.telegramName != nil } || ImportActivity.shared.count > 0)
                .appGlassButton(prominent: true, tint: .blue).accessibilityIdentifier("updateSelectedPacks")
                Button { optimizationRequest = OptimizationRequest(packIDs: bulkSelected) } label: { actionLabel("용량 최적화", icon: "slider.horizontal.3") }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .appGlassButton(prominent: true, tint: .indigo).accessibilityIdentifier("optimizeSelectedPacks")
                Button(role: .destructive) { confirmBulkDelete = true } label: { actionLabel("삭제", icon: "trash") }
                    .disabled(bulkSelected.isEmpty || ImportActivity.shared.count > 0)
                    .appGlassButton(prominent: true, tint: .red).accessibilityIdentifier("deleteSelectedPacks")
                    .confirmationDialog(LibrarySyncService.shared.enabled && LibraryChangeJournal.cloudKitConfigured ? "모든 기기에서 선택한 \(bulkSelected.count)개 팩을 삭제할까요?" : "선택한 \(bulkSelected.count)개 팩을 삭제할까요?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
                        Button("선택한 팩 삭제", role: .destructive) {
                            let ids = Array(bulkSelected)
                            bulkSelected.removeAll()
                            Task { await model.delete(ids: ids) }
                        }
                    }
            }
            .font(.subheadline)
            .buttonBorderShape(.capsule)
            .lineLimit(1)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 30, height: 30)
            .contentShape(Capsule())
    }

    private func addPack() {
        if ImportActivity.shared.current?.busy == true { ImportActivity.shared.presentCurrent() }
        else if OptimizationCenter.shared.current?.running == true { OptimizationCenter.shared.presentCurrent() }
        else { importRequest = PackImportRequest(name: nil, updating: false) }
    }

    var body: some View {
        GeometryReader { geometry in
        #if targetEnvironment(macCatalyst)
        // A narrow Mac window needs one navigation column, even when UIKit's
        // iPad idiom continues to report a regular size class.
        let wideLayout = geometry.size.width >= 760
        let sidebarMaximum = min(360, max(280, geometry.size.width / 3))
        let sidebarMinimum: CGFloat = 280
        #else
        let wideLayout = geometry.size.width >= 600 && (UIDevice.current.userInterfaceIdiom == .pad || geometry.size.width > geometry.size.height)
        let sidebarMaximum = geometry.size.width / 3
        let sidebarMinimum = min(300, sidebarMaximum)
        #endif
        let phoneLandscapeSidebar = wideLayout && UIDevice.current.userInterfaceIdiom == .phone
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            List(selection: listSelection) {
                if let message = model.message {
                    Section { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("libraryMessage") }
                }
                if !SyncDownloadCoordinator.shared.pendingPacks.isEmpty {
                    Section("iCloud에서 받은 팩") {
                        ForEach(SyncDownloadCoordinator.shared.pendingPacks) { pack in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pack.title)
                                Text(pack.status).font(.caption).foregroundStyle(pack.failed ? Color.red : Color.secondary)
                                if pack.failed { Button("다시 시도") { SyncDownloadCoordinator.shared.reconcile(retryFailures: true) } }
                            }
                            .contextMenu {
                                Button("모든 기기에서 팩 삭제", role: .destructive) { deletingPendingPack = pack.id }
                            }
                            .confirmationDialog("모든 기기에서 이 팩을 삭제할까요?", isPresented: Binding(
                                get: { deletingPendingPack == pack.id }, set: { if !$0 { deletingPendingPack = nil } }
                            ), titleVisibility: .visible) {
                                Button("팩 삭제", role: .destructive) {
                                    deletingPendingPack = nil
                                    Task { await model.delete(ids: [pack.id]) }
                                }
                            }
                        }
                    }
                }
                if model.packs.isEmpty && SyncDownloadCoordinator.shared.pendingPacks.isEmpty {
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
                        packNavigationRow(pack)
                                .contentShape(Rectangle())
                                .onDrag {
                                    guard editMode.isEditing, !model.isBusy, model.damagedPacks.isEmpty,
                                          ImportActivity.shared.count == 0 else { return NSItemProvider() }
                                    draggingPack = pack.id
                                    return NSItemProvider(object: pack.id as NSString)
                                }
                        .tag(pack.id)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
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
                                deletingPack = pack
                            }.labelStyle(.iconOnly)
                        }
                    }

                }
                .listRowBackground(listColor(.secondarySystemGroupedBackground))
                // UIKit clips the section background at the landscape notch
                // while applying its safe-area inset only to row content.
                // Keep the section's rounded edge inside that clipping boundary.
                .listSectionMargins(.leading, max(20, wideLayout ? geometry.safeAreaInsets.leading : 0))
                .listSectionMargins(.trailing, phoneLandscapeSidebar ? 8 : 20)
            }
            #if targetEnvironment(macCatalyst)
            .focusable()
            .focusEffectDisabled()
            .focused($commandFocus)
            .focusedValue(\.stickerCommands, StickerCommandActions(selectAll: {
                sharing = false; editMode = .active; bulkSelected = Set(model.packs.map(\.id))
            }))
            #endif
            .listStyle(.insetGrouped)
            .onScrollPhaseChange { _, phase in
                let active = phase != .idle
                if sidebarScrolling != active { sidebarScrolling = active }
            }
            // Keep the hard edge clear at rest and during top overscroll.
            // Normalize by the inset so the threshold survives rotation.
            .scrollEdgeEffectStyle(wideLayout ? .hard : .automatic, for: .top)
            .scrollEdgeEffectHidden(wideLayout && !sidebarScrolledUnderToolbar, for: .top)
            .onScrollGeometryChange(for: Bool.self) { scroll in
                scroll.contentOffset.y + scroll.contentInsets.top > 0.5
            } action: { _, scrolled in
                sidebarScrolledUnderToolbar = scrolled
            }
            .contentMargins(.top, wideLayout ? 8 : nil, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(listColor(.systemGroupedBackground))
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { _, mode in
                if mode == .inactive { bulkSelected.removeAll() }
            }
            .disabled(model.isBusy)
            .contentMargins(.bottom, 12 + workBannerHeight + (editMode.isEditing ? editingActionsHeight : 0), for: .scrollContent)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Group {
                        if sharing {
                            let links = PackLinkList.links(for: model.packs.filter { bulkSelected.contains($0.id) })
                            ShareLink(item: StickerLinkFile(text: links.joined(separator: "\n")), preview: SharePreview("스티커 팩 링크 목록")) {
                                Label("선택한 팩 공유", systemImage: "square.and.arrow.up")
                            }
                            .disabled(links.isEmpty)
                            .appGlassButton(prominent: true).controlSize(.large).padding(12)
                        } else { packEditingActions() }
                    }
                    .frame(height: 68)
                    // Center in the list viewport; editing shifts row content
                    // to make room for selection controls.
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(editMode.isEditing ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: editMode.isEditing)

                    .allowsHitTesting(editMode.isEditing)
                    .accessibilityHidden(!editMode.isEditing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { editingActionsHeight = $0 }
                    .frame(height: editMode.isEditing ? nil : 0)
                    CurrentWorkBanner()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { workBannerHeight = $0 }
                }
            }
            .navigationTitle(wideLayout ? "" : "내 스티커 팩")
            .navigationBarTitleDisplayMode(wideLayout ? .inline : .large)
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
        #if !targetEnvironment(macCatalyst)
        .background {
            LibraryRotationObserver {
                columnVisibility = .all
            }
        }
        #endif
        .navigationSplitViewStyle(.balanced)
        #if targetEnvironment(macCatalyst)
        .environment(\.horizontalSizeClass, wideLayout ? .regular : .compact)
        #else
        .environment(\.horizontalSizeClass, wideLayout ? .regular : systemSizeClass)
        #endif
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
        .onChange(of: compactColumn) { previous, current in
            // Compact back navigation must also dismiss the selected pack.
            // Sidebar visibility in the expanded layout does not dismiss it.
            guard !wideLayout, activeTab == .library,
                  previous == .detail, current == .sidebar else { return }
            selected = nil
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
                    .navigationBarTitleDisplayMode(.inline)

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
