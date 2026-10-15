import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor @Observable
final class ImportActivity {
    static let shared = ImportActivity()
    var count = 0
    var libraryChangeID = 0
    var current: ImportModel?
    var presentedImport: ImportModel?
    var optimizationSuggestion: OptimizationRequest?
    var visibleImportIDs = Set<UUID>()
    func suggestOptimization(packIDs: Set<String>) {
        guard !packIDs.isEmpty else { return }
        optimizationSuggestion = OptimizationRequest(packIDs: packIDs)
    }
    func presentCurrent() { presentedImport = current }
}

struct AdditionalPackLink: Identifiable {
    let id: UUID
    var value: String
    init(id: UUID = UUID(), value: String = "") { self.id = id; self.value = value }
}
struct BatchPackStatus: Identifiable {
    let id: UUID
    let link: String
    var title: String
    var status = "대기 중"
}

@MainActor @Observable
final class ImportModel: Identifiable {
    let id = UUID()
    var primaryLinkID = UUID()
    var link = ""
    var additionalLinks: [AdditionalPackLink] = []
    var batchStatuses: [BatchPackStatus] = []
    private var batchCounts: [Int: ImportProgress] = [:]
    private var batchLookupReady = false
    private var batchLookupFailures = 0
    private var batchApplied = false
    private var newlyInstalledIDs = Set<String>()
    var downloadSummary = "준비 중"
    var pack: RemotePack?
    var message: String?
    var progress: ImportProgress?
    var busy = false {
        didSet {
            if oldValue != busy {
                ImportActivity.shared.count = max(0, ImportActivity.shared.count + (busy ? 1 : -1))
                if busy { ImportActivity.shared.current = self }
            }
        }
    }
    var installed = false
    var result: ImportResult?
    var client: WorkerClient?
    var failures: [ImportFailure] = []
    var updating = false
    var restoringOriginal = false
    var singleUpdateName: String?
    var singleUpdateTitle: String?
    private let coordinator: ImportCoordinator
    private var operation: Task<Void, Never>?
    private var backgroundID: String?
    init(writer: LibraryWriter, root: URL? = nil) { coordinator = ImportCoordinator(writer: writer, root: root) }

    var installing: Bool { busy && backgroundID != nil }
    var inputLinks: [AdditionalPackLink] { [AdditionalPackLink(id: primaryLinkID, value: link)] + additionalLinks }
    var failedCount: Int { max(progress?.failed ?? 0, batchCounts.values.reduce(batchLookupFailures) { $0 + $1.failed }) }
    var progressColor: Color { failedCount > 0 ? .red : (batchApplied || progress?.applied == true || installed ? .green : .blue) }

    func setInputLinks(_ rows: [AdditionalPackLink]) {
        guard !busy, let first = rows.first else { return }
        primaryLinkID = first.id; link = first.value; additionalLinks = Array(rows.dropFirst())
        pack = nil; installed = false; result = nil
    }

    private func incompleteLinks(_ links: [String]) async -> [String] {
        await Task.detached {
            guard let reader = try? LibraryReader.shared(), let snapshot = try? reader.snapshot(resolvingFiles: false) else { return links }
            let completeNames = Set(snapshot.packs.filter {
                ($0.pendingStickerIDs ?? []).isEmpty && $0.stickers.count >= $0.originalCount
            }.compactMap { $0.telegramName?.lowercased() })
            return links.filter { link in
                guard let name = try? StickerLink.parse(link) else { return true }
                return !completeNames.contains(name.lowercased())
            }
        }.value
    }

    private var completionDetail: String {
        let detail = message ?? downloadSummary
        return !updating && !restoringOriginal && ((result?.installed ?? 0) > 0 || !newlyInstalledIDs.isEmpty)
            ? detail + " 용량 최적화로 저장 공간을 줄여보세요." : detail
    }

    func configure() async {
        guard !busy else { return }
        pack = nil; progress = nil; installed = false; result = nil; client = nil
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--import-ui-fixture") {
                client = try ImportPreviewFixture.client(); message = "로컬 테스트 데이터"; return
            }
            #endif
            guard let config = try ImportSettings.load() else {
                message = "가져오기 서비스에 연결할 수 없어요. 다시 시도해 주세요."; client = nil; return
            }
            client = WorkerClient(configuration: config)
            if !updating, let draft = try? await coordinator.batchDraft(for: config.origin) {
                let pending = await incompleteLinks(draft.links)
                if let first = pending.first {
                    link = first
                    additionalLinks = pending.dropFirst().map { AdditionalPackLink(value: $0) }
                    message = "설치가 끝나지 않은 링크를 복원했어요."
                    return
                }
            }
            if !updating, let draft = try? await coordinator.draft(for: config.origin),
               !(await incompleteLinks([draft.link])).isEmpty {
                link = draft.link; pack = draft.pack
                try await loadInstalledStatus(draft.pack)
                message = result?.message ?? "이전 가져오기를 이어서 진행할 수 있어요."
            } else { message = nil }
        } catch { message = error.localizedDescription }
    }
    func preview() {
        guard !busy, let client else { return }
        guard ImportActivity.shared.count == 0 else { message = "진행 중인 작업을 마친 뒤 이 팩의 업데이트 확인을 진행해 주세요."; return }
        busy = true; installed = false; result = nil; message = nil; progress = nil; pack = nil
        operation = Task {
            defer { busy = false }
            do {
                let name = try StickerLink.parse(link)
                let loaded = try await client.pack(name: name, refresh: updating)
                try Task.checkCancellation()
                try await coordinator.saveDraft(ImportDraft(origin: client.configuration.origin, link: link, pack: loaded))
                pack = loaded
                try await loadInstalledStatus(loaded)
                failures = await ImportFailureStore.shared.load(name: loaded.name)
                if let result { message = result.message }
            } catch is CancellationError { message = "취소했어요." }
            catch { message = error.localizedDescription }
        }
    }
    func download(onlyIDs: Set<String>? = nil) {
        guard !busy, let client, let pack else { return }
        guard ImportActivity.shared.count == 0 else { message = "진행 중인 설치·용량 최적화 작업을 먼저 마쳐 주세요."; return }
        busy = true; message = nil; downloadSummary = "준비 중"
        operation = Task {
            backgroundID = await BackgroundWork.shared.begin(kind: restoringOriginal ? .restoreOriginal : updating ? .update : .download, title: updating ? "스티커 팩 업데이트 확인" : "스티커 설치") { self.cancel() }
            var success = false
            defer { BackgroundWork.shared.end(id: backgroundID, success: success, detail: completionDetail, cancelled: Task.isCancelled); backgroundID = nil; busy = false }
            do {
                let receipt = try await coordinator.install(pack, client: client, updating: updating, onlyIDs: onlyIDs, restoringOriginal: restoringOriginal) { value in
                    await self.updateProgress(value)
                }
                result = receipt; installed = receipt.failed == 0; message = receipt.message; success = receipt.failed == 0
                ImportActivity.shared.libraryChangeID += 1
                if !updating && receipt.installed > 0 { ImportActivity.shared.suggestOptimization(packIDs: ["telegram-" + pack.name]) }
            } catch is CancellationError { message = "중단했어요. 다시 시도하면 준비된 파일을 재사용해요." }
            catch { message = error.localizedDescription }
            failures = await ImportFailureStore.shared.load(name: pack.name)
            if !success, let message { DownloadDiagnostics.shared.record("\(pack.name) · 설치 종료 · \(message)") }
        }
    }
    func downloadBatch() {
        guard !busy, let client else { return }
        guard ImportActivity.shared.count == 0 else { message = "진행 중인 설치·용량 최적화 작업을 먼저 마쳐 주세요."; return }
        let inputs = ([(id: primaryLinkID, value: link)] + additionalLinks.map { (id: $0.id, value: $0.value) })
            .flatMap { field in
                PackLinkList.split(field.value).enumerated().map { offset, value in
                    (id: offset == 0 ? field.id : UUID(), value: value)
                }
            }
        let links = inputs.map { $0.value }
        guard !links.isEmpty else { message = "팩 링크를 입력해 주세요."; return }
        batchStatuses = inputs.map { BatchPackStatus(id: $0.id, link: $0.value, title: $0.value) }
        batchCounts = [:]
        batchLookupReady = false
        batchLookupFailures = 0; batchApplied = false; newlyInstalledIDs.removeAll()
        downloadSummary = "팩 목록 조회 중"
        let batchUpdating = updating
        busy = true; message = nil; pack = nil; progress = nil; result = nil
        operation = Task {
            backgroundID = await BackgroundWork.shared.begin(kind: restoringOriginal ? .restoreOriginal : updating ? .update : .download, title: restoringOriginal ? "스티커 원본 복원" : (updating ? "스티커 팩 일괄 업데이트 확인" : "스티커 팩 일괄 설치")) { self.cancel() }
            var success = false
            defer { BackgroundWork.shared.end(id: backgroundID, success: success, detail: completionDetail, cancelled: Task.isCancelled); backgroundID = nil; busy = false }
            do {
                try await coordinator.saveBatch(BatchImportDraft(origin: client.configuration.origin, links: links, updating: batchUpdating))
                let directory = try await coordinator.beginBatch(links: links, origin: client.configuration.origin, updating: batchUpdating)
                do {
                    var seen = Set<String>()
                    var pending: [(index: Int, name: String)] = []
                    for index in links.indices {
                        do {
                            let name = try StickerLink.parse(links[index])
                            if seen.insert(name).inserted { pending.append((index, name)) }
                            else {
                                batchStatuses[index].status = "중복 링크 · 건너뜀"
                            }
                        } catch {
                            batchStatuses[index].status = "실패 · " + error.localizedDescription
                            batchLookupFailures += 1
                        }
                    }
                    reportBatchProgress()
                    // Resolve all pack sizes first so the activity has one stable
                    // item total, rather than a denominator that grows mid-download.
                    let ready = try await withThrowingTaskGroup(of: (Int, RemotePack)?.self) { group in
                        for item in pending {
                            group.addTask { @MainActor in
                                try await self.prepareBatchPack(index: item.index, name: item.name,
                                    client: client, updating: batchUpdating)
                            }
                        }
                        var packs: [(Int, RemotePack)] = []
                        for try await pack in group { if let pack { packs.append(pack) } }
                        return packs
                    }
                    batchLookupReady = true
                    reportBatchProgress()
                    // No application-level cap on simultaneous packs.
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (index, remote) in ready {
                            group.addTask { @MainActor in
                                let worker = try await self.coordinator.batchWorker(directory: directory, name: remote.name)
                                try await self.installBatchPack(index: index, remote: remote,
                                    client: client, worker: worker, updating: batchUpdating)
                            }
                        }
                        try await group.waitForAll()
                    }
                    try Task.checkCancellation()
                    try await coordinator.orderBatch(links: links)
                    ImportActivity.shared.libraryChangeID += 1
                    success = batchLookupFailures == 0 && batchCounts.values.allSatisfy { $0.failed == 0 } && !batchStatuses.contains { $0.status.hasPrefix("실패") }
                    if success { try await coordinator.saveBatch(BatchImportDraft(origin: client.configuration.origin, links: [], updating: batchUpdating)) }
                    await coordinator.endBatch(directory: directory, completed: success)
                    batchApplied = success
                    reportBatchProgress()
                } catch {
                    // The task group has joined all children before releasing
                    // the root lease, including when a user cancels the batch.
                    try? await coordinator.orderBatch(links: links)
                    ImportActivity.shared.libraryChangeID += 1
                    await coordinator.endBatch(directory: directory, completed: false)
                    throw error
                }
                message = success ? "선택한 팩을 모두 적용했어요." : "설치된 팩을 적용했어요. 실패한 팩은 다시 시도해 주세요."
                if !updating { ImportActivity.shared.suggestOptimization(packIDs: newlyInstalledIDs) }
            } catch {
                for index in batchStatuses.indices where batchStatuses[index].status == "대기 중" || batchStatuses[index].status == "다운로드 중" || batchStatuses[index].status == "팩 조회 중" || batchStatuses[index].status == "스티커 설치 중" || batchStatuses[index].status.hasPrefix("준비 ") {
                    batchStatuses[index].status = "중단됨 · 다시 시도 가능"
                }
                message = error is CancellationError ? "중단했어요. 설치 완료한 팩은 유지해요." : error.localizedDescription
            }
        }
    }

    private func prepareBatchPack(index: Int, name: String, client: WorkerClient,
                                  updating: Bool) async throws -> (Int, RemotePack)? {
        do {
            try Task.checkCancellation()
            batchStatuses[index].status = "팩 조회 중"
            let remote = try await client.pack(name: name, refresh: updating)
            try Task.checkCancellation()
            batchStatuses[index].title = remote.title
            batchStatuses[index].status = "대기 중"
            batchCounts[index] = ImportProgress(completed: 0, total: remote.stickers.count, failed: 0)
            reportBatchProgress()
            return (index, remote)
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            batchStatuses[index].status = "실패 · " + error.localizedDescription
            batchLookupFailures += 1
            DownloadDiagnostics.shared.record("\(name) · 팩 조회 실패 · \(error.localizedDescription)")
            reportBatchProgress()
            return nil
        }
    }

    private func installBatchPack(index: Int, remote: RemotePack, client: WorkerClient,
                                  worker: ImportCoordinator, updating: Bool) async throws {
        do {
            try Task.checkCancellation()
            if !updating, let installed = try await worker.installedResult(for: remote), installed.failed == 0 {
                batchStatuses[index].status = "이미 설치됨 · 건너뜀"
                batchCounts[index] = ImportProgress(completed: remote.stickers.count, total: remote.stickers.count, failed: 0, applied: true)
            } else {
                batchStatuses[index].status = "다운로드 중"
                let receipt = try await worker.install(remote, client: client, updating: updating, restoringOriginal: restoringOriginal) { value in
                    await self.updateBatchProgress(index: index, value: value)
                }
                batchCounts[index] = ImportProgress(completed: receipt.installed, total: receipt.total, failed: receipt.failed, applied: receipt.failed == 0)
                if !updating && receipt.installed > 0 { newlyInstalledIDs.insert("telegram-" + remote.name) }
                batchStatuses[index].status = receipt.failed == 0 ? "설치 완료" : "자동 재시도 종료 · 실패 항목 확인 필요"
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            batchStatuses[index].status = "실패 · " + error.localizedDescription
            DownloadDiagnostics.shared.record("\(remote.name) · 팩 설치 실패 · \(error.localizedDescription)")
            if let counts = batchCounts[index] {
                batchCounts[index] = ImportProgress(completed: counts.completed, total: counts.total,
                    failed: max(0, counts.total - counts.completed))
            }
        }
        do { try await coordinator.orderBatch(links: batchStatuses.map(\.link)) }
        catch { DownloadDiagnostics.shared.record("팩 정렬 · \(error.localizedDescription)") }
        ImportActivity.shared.libraryChangeID += 1
        reportBatchProgress()
    }

    private func updateBatchProgress(index: Int, value: ImportProgress) {
        // An update may retain old items; cap displayed counts to the remote total.
        let completed = min(value.total, max(0, value.completed))
        batchCounts[index] = ImportProgress(completed: completed, total: value.total,
            failed: min(max(0, value.failed), max(0, value.total - completed)), applied: value.applied)
        batchStatuses[index].status = value.applied ? "설치 완료" : (completed >= value.total ? "파일 적용 중" : "스티커 설치 중")
        reportBatchProgress()
    }

    private func reportBatchProgress() {
        guard batchLookupReady else {
            downloadSummary = "팩 목록 조회 중 · \(batchCounts.count)개 확인"
            BackgroundWork.shared.report(id: backgroundID, completed: 0, total: 1, subtitle: downloadSummary)
            return
        }
        let completed = batchCounts.values.reduce(0) { $0 + $1.completed }
        let failed = batchCounts.values.reduce(0) { $0 + $1.failed }
        let total = batchCounts.values.reduce(0) { $0 + $1.total }
        let value = ImportProgress(completed: completed, total: total, failed: failed, applied: batchApplied)
        downloadSummary = value.displayText
        if batchLookupFailures > 0 { downloadSummary += " · 조회 실패 \(batchLookupFailures)팩" }
        BackgroundWork.shared.report(id: backgroundID, completed: Int64(value.installedCount),
            total: Int64(total), subtitle: downloadSummary, finalized: value.applied)
    }
    func itemProgress(id: UUID) -> ImportProgress? {
        guard let index = batchStatuses.firstIndex(where: { $0.id == id }) else { return nil }
        return batchCounts[index]
    }

    private func loadInstalledStatus(_ pack: RemotePack) async throws {
        result = try await coordinator.installedResult(for: pack)
        installed = !updating && result?.failed == 0
    }
    private func updateProgress(_ value: ImportProgress) {
        progress = value
        downloadSummary = value.displayText
        BackgroundWork.shared.report(id: backgroundID, completed: Int64(value.installedCount), total: Int64(value.total), subtitle: downloadSummary, finalized: value.applied)
    }
    func cancel() { operation?.cancel() }
}

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
                        Button("링크 목록 파일 가져오기", systemImage: "doc.badge.plus") { explainLinkFile = true }
                            .buttonStyle(.glass).disabled(model.busy || updating)
                            .accessibilityIdentifier("importPackLinkFile")
                        Button { model.additionalLinks.append(AdditionalPackLink()) } label: {
                            Label("링크 추가", systemImage: "plus.circle")
                        }.buttonStyle(.glass).disabled(model.busy || updating).accessibilityIdentifier("addPackLink")
                        if !model.additionalLinks.isEmpty || PackLinkList.split(model.link).count > 1 || !model.batchStatuses.isEmpty || model.restoringOriginal {
                            Button { focusedLink = nil; model.downloadBatch() } label: {
                                Label(model.restoringOriginal ? "입력한 팩 원본 복원" : (updating ? "입력한 팩 모두 업데이트 확인" : "입력한 팩 모두 설치"), systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                            }.buttonStyle(.glassProminent).controlSize(.large)
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
                        .buttonStyle(.glass).controlSize(.large)
                        .disabled(model.busy || model.client == nil).accessibilityIdentifier("previewPack")
                    }
                    if let message = model.message { Text(message).font(.subheadline).foregroundStyle(message.contains("실패") || model.failedCount > 0 ? Color.red : Color.secondary).accessibilityIdentifier("importMessage") }
                    if let pack = model.pack, model.additionalLinks.isEmpty && PackLinkList.split(model.link).count <= 1 {
                        if pack.installableStickers.count != pack.stickers.count {
                            Text("마스크·커스텀 이모지 팩은 설치하지 않아요.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { model.download() } label: {
                            Text(updating ? (model.installed ? "업데이트 확인 완료" : "팩 업데이트 확인") : model.result.map { $0.failed > 0 ? "실패한 \($0.failed)개 다시 시도" : "설치 완료" }
                                ?? (model.progress == nil ? "스티커 설치" : "다시 시도")).frame(maxWidth: .infinity)
                        }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .disabled(model.busy || model.installed || ImportActivity.shared.count > 0 || (!updating && pack.installableStickers.isEmpty))
                            .accessibilityIdentifier("installRemotePack")
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: stickerWidth, maximum: max(stickerWidth, 88)), spacing: 8)], spacing: 8) {
                            ForEach(pack.stickers) { sticker in
                                RemoteStickerPreview(pack: pack.name, sticker: sticker, client: model.client)
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
            .navigationTitle(model.restoringOriginal ? "스티커 원본 복원" : (updating ? "스티커 팩 업데이트 확인" : "Telegram 팩 추가"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.accessibilityIdentifier("closeImport") }
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
            } message: { Text("설치한 팩의 화질을 비교하고 저장 공간을 줄일 수 있어요.") }
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
    }
}

private struct PackLinkReorderDropDelegate: DropDelegate {
    let active: Bool
    let move: () -> Void
    let finish: () -> Void
    func validateDrop(info: DropInfo) -> Bool { active }
    func dropEntered(info: DropInfo) { if active { move() } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: active ? .move : .cancel) }
    func performDrop(info: DropInfo) -> Bool {
        guard active else { return false }
        finish()
        return true
    }
}

struct RemoteStickerPreview: View {
    let pack: String
    let sticker: RemoteSticker
    let client: WorkerClient?
    @State private var image: UIImage?
    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(systemName: sticker.format == "static" ? "photo" : "play.square").foregroundStyle(.secondary) }
            }.padding(6).frame(height: 64).frame(maxWidth: .infinity)
                .background(Color(uiColor: .tertiarySystemFill).opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if sticker.format != "static" {
                        Text("GIF").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).padding(4)
                    }
                }
            Text(sticker.emoji ?? "스티커").font(.caption2).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .task(id: sticker.id) {
            guard sticker.hasThumbnail, let client else { return }
            do {
                let data = try await client.asset(pack: pack, sticker: sticker, thumbnail: true)
                let decoded = await Task.detached { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceGetCount(source) == 1,
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 1024, height <= 1024 else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 160
                    ] as CFDictionary)
                }.value
                guard !Task.isCancelled else { return }
                image = decoded.map { UIImage(cgImage: $0) }
            } catch { image = nil }
        }
    }
}

struct DownloadLogsView: View {
    @State private var selection = Set<UUID>()
    @State private var editMode = EditMode.inactive
    @State private var copied = false
    @State private var copiedLogID: UUID?
    private var logs: [DownloadLogEntry] { Array(DownloadDiagnostics.shared.entries.reversed()) }
    var body: some View {
        List {
            if logs.isEmpty { Text("아직 기록된 로그가 없어요.").foregroundStyle(.secondary) }
            ForEach(logs) { entry in
                Button {
                    if editMode.isEditing {
                        if !selection.insert(entry.id).inserted { selection.remove(entry.id) }
                    } else {
                        copy([entry]); copiedLogID = entry.id
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if editMode.isEditing {
                            Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(entry.id) ? Color.accentColor : Color.secondary)
                                .font(.title3)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.date.ISO8601Format()).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if copiedLogID == entry.id && !editMode.isEditing {
                                    Label("복사됨", systemImage: "checkmark").font(.caption).foregroundStyle(.tint)
                                }
                            }
                            Text(entry.detail).font(.footnote.monospaced()).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(editMode.isEditing ? "로그 선택 또는 해제" : "탭하면 로그를 복사해요.")
            }
        }
        .navigationTitle("다운로드 로그")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "완료" : "선택") {
                    withAnimation(.smooth(duration: 0.25)) {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.removeAll(); copied = false; copiedLogID = nil
                    }
                }.disabled(logs.isEmpty)
                Button("비우기", role: .destructive) {
                    DownloadDiagnostics.shared.clear(); selection.removeAll(); editMode = .inactive; copiedLogID = nil
                }.disabled(logs.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editMode.isEditing {
                HStack(spacing: 12) {
                    Button(selection.count == logs.count ? "선택 해제" : "전체 선택") {
                        selection = selection.count == logs.count ? [] : Set(logs.map(\.id))
                    }
                    Spacer(minLength: 0)
                    Button(copied ? "복사됨" : "선택한 로그 복사 (\(selection.count))") {
                        copy(logs.filter { selection.contains($0.id) }); copied = true
                    }.disabled(selection.isEmpty)
                }
                .font(.subheadline).buttonStyle(.glass).lineLimit(1)
                .padding(12).frame(maxWidth: .infinity).background(.bar)
            }
        }
        .onChange(of: selection) { _, _ in copied = false }
    }
    private func copy(_ entries: [DownloadLogEntry]) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = "StickerBridge \(version) (\(build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)"
        UIPasteboard.general.string = header + "\n" + entries
            .map { "[\($0.date.ISO8601Format())] \($0.detail)" }.joined(separator: "\n\n")
    }
}
