import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

struct ImportView: View {
    @ScaledMetric(relativeTo: .caption) private var stickerWidth = 64
    @State private var model: ImportModel
    @State private var importLinkFile = false
    @State private var deletingLink: UUID?
    @State private var draggingLink: UUID?
    @State private var explainLinkFile = false
    @State private var postInstallOptimization: OptimizationRequest?
    private let initialPackName: String?
    private let updating: Bool
    private let initialLinks: [String]
    private let resumesSession: Bool
    @FocusState private var focusedLink: UUID?
    @Environment(\.dismiss) private var dismiss
    init(writer: LibraryWriter, initialPackName: String? = nil, updating: Bool = false, initialLinks: [String] = [], initialPackTitle: String? = nil) {
        if initialPackName == nil, initialLinks.isEmpty, let current = ImportActivity.shared.current, current.busy {
            _model = State(initialValue: current)
            self.initialPackName = nil; self.updating = current.updating; self.initialLinks = []
            resumesSession = true
        } else {
            let created = ImportModel(writer: writer)
            if updating { created.singleUpdateName = initialPackName; created.singleUpdateTitle = initialPackTitle }
            _model = State(initialValue: created)
            self.initialPackName = initialPackName; self.updating = updating; self.initialLinks = initialLinks
            resumesSession = false
        }
    }
    init(model: ImportModel) {
        _model = State(initialValue: model)
        initialPackName = nil; updating = model.updating; initialLinks = []
        resumesSession = true
    }
    private func linkValue(for entry: AdditionalPackLink) -> Binding<String> {
        Binding(
            get: { model.inputLinks.first(where: { $0.id == entry.id })?.value ?? entry.value },
            set: { value in
                guard !model.busy, model.inputLinks.first(where: { $0.id == entry.id })?.value != value else { return }
                if entry.id == model.primaryLinkID {
                    model.link = value; model.pack = nil; model.installed = false; model.result = nil
                } else if let index = model.additionalLinks.firstIndex(where: { $0.id == entry.id }) {
                    model.additionalLinks[index].value = value
                }
            }
        )
    }

    private func moveLink(to target: UUID) {
        guard !model.busy, let dragged = draggingLink, dragged != target else { return }
        var rows = model.inputLinks
        guard let from = rows.firstIndex(where: { $0.id == dragged }), let to = rows.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.smooth(duration: 0.25)) {
            rows.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            model.setInputLinks(rows)
        }
    }

    private func previewPack() {
        focusedLink = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            await Task.yield()
            model.preview()
        }
    }

    private func readLinks(_ result: Result<[URL], Error>) {
        guard !model.busy else { return }
        do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let links = try PackLinkList.read(url)
            let existing = model.inputLinks.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            model.setInputLinks(existing + links.map { AdditionalPackLink(value: $0) })
            model.message = "링크 \(links.count)개를 가져왔어요."
        } catch { model.message = "링크 파일을 열 수 없어요. " + error.localizedDescription }
    }

    @ViewBuilder
    private func progressDisplay(_ progress: ImportProgress) -> some View {
        ProgressView(value: progress.fraction)
            .tint(progress.failed > 0 ? .red : (progress.applied ? .green : .blue))
        Text(progress.displayText).font(.caption2.monospacedDigit())
            .foregroundStyle(progress.failed > 0 ? Color.red : Color.secondary)
    }

    private func linkInput(_ value: Binding<String>) -> some View {
        TextField("https://t.me/addstickers/…", text: value)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            .lineLimit(1)
            .textFieldStyle(.plain).padding(12).frame(minHeight: 44)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func linkStatus(id: UUID, value: String) -> some View {
        let entries = PackLinkList.split(value)
        let matches = model.batchStatuses.filter { item in
            entries.count > 1 ? entries.contains(item.link) : (item.id == id && item.link == entries.first)
        }
        if !matches.isEmpty {
            ForEach(matches) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title == item.link ? "팩 이름 조회 중" : item.title).font(.subheadline.bold()).lineLimit(2)
                    Text(item.status).font(.caption).foregroundStyle(item.status.contains("실패") ? .red : .secondary)
                    if let progress = model.itemProgress(id: item.id) {
                        progressDisplay(progress)
                    }
                }.padding(.horizontal, 4).padding(.bottom, 8)
            }
        } else if id == model.primaryLinkID, let pack = model.pack {
            VStack(alignment: .leading, spacing: 5) {
                if model.singleUpdateName == nil { Text(pack.title).font(.subheadline.bold()) }
                Text("전체 \(pack.stickers.count)개 · 설치 대상 \(pack.installableStickers.count)개").font(.caption).foregroundStyle(.secondary)
                if let progress = model.progress {
                    progressDisplay(progress)
                }
            }.padding(.horizontal, 4)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.busy {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.downloadSummary).font(.subheadline.monospacedDigit())
                                .foregroundStyle(model.failedCount > 0 ? Color.red : Color.secondary)
                            ProgressView(value: BackgroundWork.shared.fraction).tint(model.progressColor)
                        }
                    }
                    if let name = model.singleUpdateName {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.pack?.title ?? model.singleUpdateTitle ?? name).font(.title2.bold())
                            Text("Telegram 원본에서 이 팩의 새 스티커와 변경 사항을 확인해요.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("https://t.me/addstickers/" + name)
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            linkStatus(id: model.primaryLinkID, value: model.link)
                        }
                    } else {
                    Text("Telegram 공개 팩 링크를 추가하세요.").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(initialPackName == nil ? model.inputLinks : Array(model.inputLinks.prefix(1))) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                linkInput(linkValue(for: entry))
                                    .accessibilityIdentifier(entry.id == model.primaryLinkID ? "packLink" : "packLink.\(entry.id)")
                                    .focused($focusedLink, equals: entry.id).submitLabel(.done)
                                    .onSubmit { focusedLink = nil }
                                if initialPackName == nil {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.secondary).frame(width: 28, height: 44)
                                        .accessibilityLabel("길게 눌러 링크 순서 변경")
                                    Button { deletingLink = entry.id } label: {
                                        Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                    }.accessibilityLabel("링크 삭제")
                                    .confirmationDialog("이 링크를 삭제할까요?", isPresented: Binding(
                                        get: { deletingLink == entry.id },
                                        set: { if !$0 { deletingLink = nil } }
                                    ), titleVisibility: .visible) {
                                        Button("링크 삭제", role: .destructive) {
                                            let rows = model.inputLinks.filter { $0.id != entry.id }
                                            model.setInputLinks(rows.isEmpty ? [AdditionalPackLink()] : rows)
                                            deletingLink = nil
                                        }
                                        Button("취소", role: .cancel) { deletingLink = nil }
                                    }
                                }
                            }.disabled(model.busy)
                            linkStatus(id: entry.id, value: entry.value)
                        }
                        .onDrag {
                            guard !model.busy, initialPackName == nil, model.inputLinks.count > 1 else { return NSItemProvider() }
                            focusedLink = nil; draggingLink = entry.id
                            return NSItemProvider(object: entry.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: PackLinkReorderDropDelegate(
                            active: draggingLink != nil && !model.busy,
                            move: { moveLink(to: entry.id) }, finish: { draggingLink = nil }
                        ))
                    }
                    if initialPackName == nil {
                        HStack(spacing: 8) {
                            Button("링크 목록 파일 가져오기", systemImage: "doc.badge.plus") { explainLinkFile = true }
                                .appGlassButton().disabled(model.busy || updating)
                                .accessibilityIdentifier("importPackLinkFile")
                            Spacer(minLength: 0)
                            Button { model.additionalLinks.append(AdditionalPackLink()) } label: {
                                Label("링크 추가", systemImage: "plus.circle")
                            }.appGlassButton().disabled(model.busy || updating).accessibilityIdentifier("addPackLink")
                        }
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        if !model.additionalLinks.isEmpty || PackLinkList.split(model.link).count > 1 || !model.batchStatuses.isEmpty || model.restoringOriginal {
                            Button { focusedLink = nil; model.downloadBatch() } label: {
                                Label(model.restoringOriginal ? "입력한 팩 원본 복원" : (updating ? "모두 업데이트" : "입력한 팩 모두 설치"), systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                            }.appGlassButton(prominent: true).controlSize(.large)
                                .disabled(model.busy || model.client == nil).accessibilityIdentifier("installBatch")
                            Text("입력한 팩을 동시에 다운로드해요. 한 팩이 실패해도 다른 팩은 계속하고, 이미 설치한 팩과 중복 링크는 건너뛰어요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    }
                    if model.additionalLinks.isEmpty && PackLinkList.split(model.link).count == 1 {
                    Button { previewPack() } label: {
                        Label(model.singleUpdateName == nil ? "팩 미리보기" : "업데이트 확인", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }
                        .appGlassButton().controlSize(.large)
                        .disabled(model.busy || model.client == nil).accessibilityIdentifier("previewPack")
                    }
                    if let message = model.message { Text(message).font(.subheadline).foregroundStyle(message.contains("실패") || model.failedCount > 0 ? Color.red : Color.secondary).accessibilityIdentifier("importMessage") }
                    if let pack = model.pack, model.additionalLinks.isEmpty && PackLinkList.split(model.link).count <= 1 {
                        if pack.installableStickers.count != pack.stickers.count {
                            Text("마스크·커스텀 이모지 팩은 설치하지 않아요.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if !updating || model.restoringOriginal || model.installed || model.updateEntry?.difference.hasChanges(in: model.updateScope) == true {
                        Button { model.download() } label: {
                            let title = model.restoringOriginal ? (model.installed ? "원본 복원 완료" : "원본 복원") : updating ? (model.installed ? "업데이트 완료" : "업데이트") : model.result.map { $0.failed > 0 ? "실패한 \($0.failed)개 다시 시도" : "설치 완료" }
                                ?? (model.progress == nil ? "스티커 설치" : "다시 시도")
                            Text(title).frame(maxWidth: .infinity)
                        }
                            .appGlassButton(prominent: true).controlSize(.large)
                            .disabled(model.busy || model.installed || ImportActivity.shared.count > 0 || (!updating && pack.installableStickers.isEmpty))
                            .accessibilityIdentifier("installRemotePack")
                        }
                        if !model.failures.isEmpty {
                            DisclosureGroup("실패 항목 보기 (\(model.failures.count))") {
                                ForEach(model.failures) { failure in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("항목 \((pack.stickers.firstIndex(where: { $0.id == failure.id }) ?? -1) + 1) · \(failure.format) · \(failure.stage) · \(failure.code)").font(.caption.bold())
                                        Text(failure.message).font(.caption)
                                        Button("이 항목 재시도") { model.download(onlyIDs: [failure.id]) }.disabled(model.busy || model.installed)
                                    }.padding(.vertical, 6)
                                }
                            }.foregroundStyle(.red).accessibilityIdentifier("importFailures")
                        }
                        if updating, !model.restoringOriginal, let entry = model.updateEntry {
                            PackUpdateChangesView(entry: entry, client: model.client)
                        } else if !updating || model.restoringOriginal {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: stickerWidth, maximum: max(stickerWidth, 88)), spacing: 8)], spacing: 8) {
                            ForEach(pack.stickers) { sticker in
                                RemoteStickerPreview(pack: pack.name, sticker: sticker, client: model.client)
                            }
                        }
                        }
                        DisclosureGroup("복사 방식과 지원 형식") {
                            Text("일부 항목이 실패해도 성공한 스티커는 바로 설치해요. 실패한 항목만 나중에 다시 가져올 수 있어요.")
                            Text("TGS·WebM은 GIF로 변환해요. 붙여넣는 앱에 따라 움직임·투명도가 달라지며, PNG로도 복사할 수 있어요.")
                            Text("팩 제작자의 이용 조건을 확인해 주세요.")
                        }.font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.busy {
                        if let notice = BackgroundWork.shared.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                        else { Text("앱을 나가도 계속 진행해요. 진행 상황은 시스템 Live Activity에서 확인할 수 있어요.").font(.caption).foregroundStyle(.secondary) }
                        ProgressView()
                        Button("취소") { model.cancel() }
                    }
                }.padding().frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .modifier(KeyboardPermissionReminder(working: model.installing))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.restoringOriginal ? "스티커 원본 복원" : (updating ? "스티커 팩 업데이트" : "Telegram 팩 추가"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppModalCloseToolbar(accessibilityID: "closeImport") { dismiss() }
            }
            .alert("링크 목록 파일 가져오기", isPresented: $explainLinkFile) {
                Button("파일 선택") { importLinkFile = true }
                Button("취소", role: .cancel) { }
            } message: { Text(".stickerlinks로 끝나는 파일을 가져와 주세요.") }
            .alert("스티커 용량을 줄여볼까요?", isPresented: Binding(
                get: { ImportActivity.shared.optimizationSuggestion != nil && ImportActivity.shared.visibleImportIDs.contains(model.id) },
                set: { if !$0 { ImportActivity.shared.optimizationSuggestion = nil } }
            )) {
                Button("용량 최적화") {
                    postInstallOptimization = ImportActivity.shared.optimizationSuggestion
                    ImportActivity.shared.optimizationSuggestion = nil
                }
                Button("나중에", role: .cancel) { ImportActivity.shared.optimizationSuggestion = nil }
            } message: { Text("이번에 받은 스티커만 화질을 비교하고 최적화해요. 기존 스티커는 유지해요.") }
            .sheet(item: $postInstallOptimization) { OptimizationView(request: $0) }
            .onAppear { ImportActivity.shared.visibleImportIDs.insert(model.id) }
            .onDisappear { ImportActivity.shared.visibleImportIDs.remove(model.id) }
            .fileImporter(isPresented: $importLinkFile, allowedContentTypes: [.stickerBridgeLinks, .plainText], allowsMultipleSelection: false, onCompletion: readLinks)
            .task {
                guard !resumesSession else { return }
                model.updating = updating
                await model.configure()
                if let first = initialLinks.first {
                    model.link = first
                    model.additionalLinks = initialLinks.dropFirst().map { var item = AdditionalPackLink(); item.value = $0; return item }
                    model.downloadBatch()
                } else if let name = initialPackName, StickerLink.validName(name) {
                    model.link = "https://t.me/addstickers/" + name; model.preview()
                }
            }
        }
        .appModalBackground()
    }
}
