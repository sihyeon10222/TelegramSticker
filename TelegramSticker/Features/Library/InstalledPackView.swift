import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct InstalledPackView: View {
    @Environment(\.activeAppTab) private var activeTab
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let landscape: Bool
    let pack: PackManifestV1
    let stickers: [Sticker]
    let update: () -> Void
    let refresh: () async -> Void
    let retry: () -> Void
    let optimize: (Set<String>) -> Void
    let delete: () async -> Void
    @State private var scrolling = false
    @State private var status = "두 손가락으로 확대하거나 축소할 수 있어요."
    @FocusState private var commandFocus: Bool
    @State private var focusedStickerID: String?
    @State private var copyGenerations: [String: Int] = [:]
    @State private var sharedPNG: SharedPNG?
    @State private var permissionWarning = false
    @State private var confirmDelete = false
    @State private var confirmStickerDelete = false
    @State private var deletionIDs = Set<String>()
    @State private var selecting = false
    @State private var selectionOptimizationPending = false
    @State private var selectedStickers = Set<String>()
    @State private var stickerFrames: [String: CGRect] = [:]
    @State private var selectionGestureGeneration = 0
    @State private var columnCount = 4
    @AppStorage("library.stickerGrid.columns.v1") private var savedColumnCount = 0
    @State private var pinchStartColumns: Int?
    @GestureState private var pinching = false
    @State private var suppressTapUntil = Date.distantPast
    @State private var storageBytes: Int64?
    @State private var stickerStorageBytes: [String: Int64] = [:]

    private var usesLandscapeTitle: Bool {
        #if targetEnvironment(macCatalyst)
        // Let the navigation bar lay out and truncate its title during live resize.
        false
        #else
        landscape
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private func adjustColumnsForKeyboard(by delta: Int) {
        guard !pinching else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)) {
            columnCount = min(10, max(2, columnCount + delta))
            savedColumnCount = columnCount
        }
    }
    #endif

    private var gridZoom: some Gesture {
        MagnifyGesture()
            .updating($pinching) { _, pinching, _ in pinching = true }
            .onChanged { value in
                suppressTapUntil = Date().addingTimeInterval(0.35)
                let startingColumns = pinchStartColumns ?? columnCount
                pinchStartColumns = startingColumns
                let columns = min(10, max(2, Int((Double(startingColumns) / value.magnification).rounded())))
                guard columns != columnCount else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)) {
                    columnCount = columns
                    savedColumnCount = columns
                }
            }
            .onEnded { _ in
                pinchStartColumns = nil
                suppressTapUntil = Date().addingTimeInterval(0.35)
            }
    }
    @Environment(\.dismiss) private var dismiss

    private var gridContent: some View {
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
                if let entry = PackUpdateService.shared.entries[pack.id], entry.difference.hasChanges {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("업데이트할 내용이 있어요").font(.headline)
                        Text(entry.difference.summary).font(.caption).foregroundStyle(.secondary)
                        Button("업데이트 보기", action: update)
                            .accessibilityIdentifier("installedPackUpdates")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
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
                            InstalledStickerPreview(sticker: sticker,
                                paused: scrolling || pinching || activeTab != .library || scenePhase != .active || reduceMotion)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                            .modifier(StickerCopyFeedback(generation: copyGenerations[sticker.id, default: 0], reduceMotion: reduceMotion))
                            .padding(3).frame(maxWidth: .infinity).frame(height: cellWidth)
                            .background(Color(uiColor: .tertiarySystemFill).opacity(0.35),
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
                        .background {
                            if selecting {
                                GeometryReader { cell in
                                    Color.clear.preference(key: StickerSelectionFrames.self,
                                        value: [sticker.id: cell.frame(in: .named("stickerSelectionGrid"))])
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !pinching, Date() >= suppressTapUntil else { return }
                            #if targetEnvironment(macCatalyst)
                            commandFocus = true
                            focusedStickerID = sticker.id
                            #endif
                            if selecting {
                                if !selectedStickers.insert(sticker.id).inserted { selectedStickers.remove(sticker.id) }
                            } else {
                                copy(sticker)
                            }
                        }
                        .accessibilityLabel(sticker.animationURL == nil ? sticker.name : "\(sticker.name), 애니메이션")
                        .accessibilityHint(selecting ? "탭하면 선택하거나 해제해요." : "탭하면 바로 복사해요. 길게 누르거나 우클릭하면 복사, 공유, 용량 최적화와 삭제 옵션을 열 수 있어요.")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(selecting && selectedStickers.contains(sticker.id) ? .isSelected : [])
                        .accessibilityIdentifier("installedCopy.\(sticker.id)")
                        .contextMenu {
                            if let bytes = stickerStorageBytes[sticker.id] {
                                Text("저장 용량 \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                            }
                            Button("복사", systemImage: "doc.on.doc") { copy(sticker) }
                            if sticker.animationURL != nil { Button("PNG로 복사", systemImage: "photo") { copy(sticker, asPNG: true) } }
                            Button("공유", systemImage: "square.and.arrow.up") { share(sticker, animated: sticker.animationURL != nil) }
                            Button("용량 최적화", systemImage: "slider.horizontal.3") { optimize([sticker.id]) }
                                .disabled(ImportActivity.shared.count > 0)
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                deletionIDs = [sticker.id]
                                confirmStickerDelete = true
                            }
                            .foregroundStyle(.red)
                            .disabled(ImportActivity.shared.count > 0)
                        }
                    }
                }
                .coordinateSpace(name: "stickerSelectionGrid")
                .onPreferenceChange(StickerSelectionFrames.self) {
                    if stickerFrames != $0 { stickerFrames = $0 }
                }
                .background {
                    if selecting {
                    StickerDragSelection(active: selecting && !pinching,
                                         generation: selectionGestureGeneration,
                                         frames: stickerFrames, orderedIDs: stickers.map(\.id), selection: $selectedStickers,
                                         began: { suppressTapUntil = .distantFuture },
                                         ended: { suppressTapUntil = Date().addingTimeInterval(0.35) })
                    }
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .onScrollPhaseChange { _, phase in
            let active = phase != .idle
            if scrolling != active { scrolling = active }
        }
        .onChange(of: geometry.size) { _, _ in selectionGestureGeneration += 1 }
        .simultaneousGesture(gridZoom)
        .refreshable { await refresh() }
        }
    }

    private var navigationContent: some View {
        gridContent
        #if targetEnvironment(macCatalyst)
        .focusedSceneValue(\.stickerGridZoom, activeTab == .library ? StickerGridZoomActions(
            zoomIn: { adjustColumnsForKeyboard(by: -1) },
            zoomOut: { adjustColumnsForKeyboard(by: 1) }
        ) : nil)
        .focusable()
        .focusEffectDisabled()
        .focused($commandFocus)
        .focusedValue(\.stickerCommands, StickerCommandActions(copy: {
            if let sticker = stickers.first(where: { $0.id == focusedStickerID }) { copy(sticker) }
        }, selectAll: {
            selecting = true; selectedStickers = Set(stickers.map(\.id))
        }))
        #endif
        .onChange(of: columnCount) { _, value in
            selectionGestureGeneration += 1
            if pinchStartColumns != nil || savedColumnCount != 0 { savedColumnCount = min(10, max(2, value)) }
        }
        .onChange(of: savedColumnCount) { _, value in
            if (2...10).contains(value), columnCount != value { columnCount = value }
            else if value == 0 { columnCount = horizontalSizeClass == .regular ? 5 : 4 }
        }
        .onChange(of: horizontalSizeClass) { _, _ in selectionGestureGeneration += 1 }
        .onChange(of: pinching) { _, active in
            if !active {
                pinchStartColumns = nil
                suppressTapUntil = Date().addingTimeInterval(0.35)
            }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            columnCount = (2...10).contains(savedColumnCount) ? savedColumnCount : (sizeClass == .regular ? 5 : 4)
            pinchStartColumns = nil
        }
        .onChange(of: ImportActivity.shared.libraryChangeID) { _, _ in
            if selectionOptimizationPending { SelectionControls.update { resetSelection() } }
        }
        .onChange(of: ImportActivity.shared.count) { previous, count in
            if previous > 0, count == 0, selectionOptimizationPending {
                SelectionControls.update { resetSelection() }
            }
        }
        .onChange(of: activeTab) { _, tab in
            if tab != .library { resetSelection() }
        }
        .navigationTitle(usesLandscapeTitle ? "" : pack.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if usesLandscapeTitle {
                ToolbarItem(placement: .principal) {
                    LandscapePackTitle(title: pack.title)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            SelectionControls(id: "stickerSelection", active: selecting, title: "선택", toggle: toggleSelection)
            ToolbarItem(id: "stickerShare", placement: .topBarTrailing) {
                PackLinkShareButton(text: PackLinkList.links(for: [pack]).joined(separator: "\n"), disabled: selecting)
                .background {
                    if usesLandscapeTitle { PackTitleBoundary(leading: false) }
                }
            }
            ToolbarItem(id: "stickerOptions", placement: .topBarTrailing) {
                packOptions
            }
        }
    }

    var body: some View {
        navigationContent
        .alert("키보드 전체 접근을 확인해 주세요", isPresented: $permissionWarning) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("확인", role: .cancel) {}
        } message: { Text("앱에서 복사는 가능하지만, 키보드에서 복사하려면 전체 접근이 필요해요. 설정 → StickerBridge → 키보드에서 허용하고 키보드를 한 번 열어 주세요.") }
        .confirmationDialog("\(deletionIDs.count)개 스티커를 삭제할까요?", isPresented: $confirmStickerDelete, titleVisibility: .visible) {
            Button("스티커 삭제", role: .destructive) {
                let ids = Set(pack.stickers.filter { deletionIDs.contains(pack.id + "." + $0.id) }.map(\.id))
                Task {
                    do {
                        guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                        try await writer.deleteStickers(packID: pack.id, revision: pack.revision, ids: ids)
                        await PackUpdateService.shared.didDeleteStickers(packID: pack.id, telegramName: pack.telegramName)
                        ImportActivity.shared.libraryChangeID += 1
                        SelectionControls.update { resetSelection() }
                        deletionIDs.removeAll()
                    } catch { status = error.localizedDescription }
                }
            }
            .foregroundStyle(.red)
        }
        .sheet(item: $sharedPNG) { PNGShareSheet(data: $0.data, type: $0.type).presentationDetents([.medium, .large]) }
        .task(id: pack.id + "." + pack.revision) {
            let bytes = await loadStorageBytes()
            guard !Task.isCancelled else { return }
            storageBytes = bytes?.total
            stickerStorageBytes = bytes?.stickers ?? [:]
        }
    }

    private func loadStorageBytes() async -> (total: Int64, stickers: [String: Int64])? {
            let pack = pack
            return await Task.detached(priority: .utility) { () -> (total: Int64, stickers: [String: Int64])? in
                guard let reader = try? LibraryReader.shared() else { return nil }
                var paths = Set<String>()
                for record in pack.stickers {
                    paths.insert(record.pngPath)
                    paths.insert(record.thumbnailPath)
                    if let path = record.animationPath { paths.insert(path) }
                    if let path = record.playbackPath { paths.insert(path) }
                }
                paths.insert("packs/\(pack.id)/\(pack.revision)/manifest.json")
                var checkedDirectories = Set<String>()
                var total: Int64 = 0
                var sizes: [String: Int64] = [:]
                for path in paths {
                    guard let url = try? reader.file(path, checkedDirectories: &checkedDirectories),
                          let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true, let size = values.fileSize else { continue }
                    total += Int64(size)
                    sizes[path] = Int64(size)
                }
                let stickerSizes = Dictionary(uniqueKeysWithValues: pack.stickers.map { record in
                    let paths = Set([record.pngPath, record.thumbnailPath, record.animationPath, record.playbackPath].compactMap { $0 })
                    return (record.id, paths.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) })
                })
                return (total, stickerSizes)
            }.value
    }

    private func toggleSelection() {
        SelectionControls.update {
            selecting.toggle()
            selectedStickers.removeAll()
        }
    }

    private var packOptions: some View {
        Menu {
                    if pack.telegramName != nil {
                        Button("업데이트 확인", systemImage: "arrow.clockwise", action: update)
                            .disabled(selecting || ImportActivity.shared.count > 0)
                            .accessibilityIdentifier("updatePack")
                    }
                    Button {
                        selectionOptimizationPending = selecting
                        optimize(selecting ? selectedStickers : [])
                    } label: {
                        let title = selecting ? "선택한 \(selectedStickers.count)개 용량 최적화" : "용량 최적화"
                        Label(title, systemImage: "slider.horizontal.3")
                    }
                    .disabled(ImportActivity.shared.count > 0 || (selecting && selectedStickers.isEmpty))
                    .accessibilityIdentifier("optimizePack")
                    if selecting {
                        Button("선택한 스티커 삭제", systemImage: "trash", role: .destructive) { deletionIDs = selectedStickers; confirmStickerDelete = true }
                        .foregroundStyle(.red)
                            .disabled(selectedStickers.isEmpty || ImportActivity.shared.count > 0)
                    } else {
                        Button("팩 삭제", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .foregroundStyle(.red)
                            .disabled(ImportActivity.shared.count > 0)
                    }
                } label: { Label("옵션", systemImage: "ellipsis") }
                    .labelStyle(.iconOnly).accessibilityIdentifier("packOptions")
                    .confirmationDialog(LibrarySyncService.shared.enabled && LibraryChangeJournal.cloudKitConfigured ? "모든 기기에서 이 팩을 삭제할까요?" : "이 팩을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("팩 삭제", role: .destructive) { Task { await delete(); dismiss() } }
                    }
    }

    private func copy(_ sticker: Sticker, asPNG: Bool = false) {
        #if !targetEnvironment(macCatalyst)
        permissionWarning = KeyboardAccessReceipt.lastAllowed == nil
        #endif
        let result = StickerCopyService().copy(sticker, isAllowed: true, asPNG: asPNG)
        if result == .copied {
            copyGenerations[sticker.id, default: 0] += 1
            status = "두 손가락으로 확대하거나 축소할 수 있어요."
        } else { status = result.message }
        UIAccessibility.post(notification: .announcement, argument: result.message)
    }

    private func share(_ sticker: Sticker, animated: Bool) {
        do {
            guard let url = animated ? sticker.animationURL : sticker.fileURL() else { throw LibraryError.invalidImage }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard animated ? GIFValidation.isValid(data) : PNGValidation.isValid(data) else { throw LibraryError.invalidImage }
            sharedPNG = SharedPNG(data: data, type: animated ? "com.compuserve.gif" : "public.png")
        } catch { status = "이미지를 공유할 수 없어요. 팩을 다시 확인해 주세요." }
    }
    private func resetSelection() {
        selectionOptimizationPending = false
        selectionGestureGeneration += 1
        selecting = false
        selectedStickers.removeAll()
        confirmDelete = false
        confirmStickerDelete = false
    }

}

/// A local, finite acknowledgement; repeated copies of the same sticker restart it.
private struct StickerCopyFeedback: ViewModifier {
    let generation: Int
    let reduceMotion: Bool
    private struct Frame {
        var scale: CGFloat = 1
        var badgeOpacity: Double = 0
    }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Frame(), trigger: generation) { preview, frame in
            preview
                .scaleEffect(reduceMotion ? 1 : frame.scale)
                .overlay {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(9)
                        .glassEffect(.regular, in: Circle())
                        .opacity(frame.badgeOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.9, duration: 0.1)
                CubicKeyframe(1.05, duration: 0.16)
                CubicKeyframe(1, duration: 0.16)
            }
            KeyframeTrack(\.badgeOpacity) {
                LinearKeyframe(1, duration: 0.08)
                LinearKeyframe(1, duration: 0.28)
                LinearKeyframe(0, duration: 0.2)
            }
        }
    }
}

/// Visibility changes stay local to each cell instead of invalidating the whole pack.
private struct InstalledStickerPreview: View {
    let sticker: Sticker
    let paused: Bool
    @State private var visible = false

    var body: some View {
        StickerLargePreview(sticker: sticker, paused: paused || !visible)
            .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
    }
}
