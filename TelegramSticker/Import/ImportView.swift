import SwiftUI
import ImageIO

@MainActor @Observable
final class ImportActivity {
    static let shared = ImportActivity()
    var count = 0
    var libraryChangeID = 0
    var current: ImportModel?
    var presentedImport: ImportModel?
    func presentCurrent() { presentedImport = current }
}

struct AdditionalPackLink: Identifiable {
    let id = UUID()
    var value = ""
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
    var link = ""
    var additionalLinks: [AdditionalPackLink] = []
    var batchStatuses: [BatchPackStatus] = []
    private var batchCounts: [Int: ImportProgress] = [:]
    private var batchLookupReady = false
    private var batchLookupFailures = 0
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
    private let coordinator: ImportCoordinator
    private var operation: Task<Void, Never>?
    private var backgroundID: String?
    init(writer: LibraryWriter, root: URL? = nil) { coordinator = ImportCoordinator(writer: writer, root: root) }

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
                message = "먼저 연결 설정에서 가져오기 서버를 설정해 주세요."; client = nil; return
            }
            client = WorkerClient(configuration: config)
            if !updating, let draft = try? await coordinator.batchDraft(for: config.origin), let first = draft.links.first {
                link = first
                additionalLinks = draft.links.dropFirst().map { var item = AdditionalPackLink(); item.value = $0; return item }
                // The presenting screen owns the operation mode. A saved update
                // batch can supply links for reinstalling deleted packs, but must
                // never turn the + screen's new installation into an update.
                message = "이전 일괄 설치 목록을 복원했어요. 다시 시작하면 설치 완료한 팩은 건너뛰어요."
                return
            }
            if let draft = try? await coordinator.draft(for: config.origin) {
                link = draft.link; pack = draft.pack
                try await loadInstalledStatus(draft.pack)
                message = result?.message ?? "이전 가져오기를 복원했어요. 다시 시도하면 준비된 파일을 재사용해요."
            } else { message = nil }
        } catch { message = error.localizedDescription }
    }
    func preview() {
        guard !busy, let client else { return }
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
        guard ImportActivity.shared.count == 0 else { message = "진행 중인 설치·최적화 작업을 먼저 마쳐 주세요."; return }
        busy = true; message = nil; downloadSummary = "준비 중"
        operation = Task {
            backgroundID = await BackgroundWork.shared.begin(title: updating ? "스티커 팩 업데이트" : "스티커 설치") { self.cancel() }
            var success = false
            defer { BackgroundWork.shared.end(id: backgroundID, success: success); backgroundID = nil; busy = false }
            do {
                let receipt = try await coordinator.install(pack, client: client, updating: updating, onlyIDs: onlyIDs, restoringOriginal: restoringOriginal) { value in
                    await self.updateProgress(value)
                }
                result = receipt; installed = receipt.failed == 0; message = receipt.message; success = receipt.failed == 0
                ImportActivity.shared.libraryChangeID += 1
            } catch is CancellationError { message = "중단했어요. 다시 시도하면 준비된 파일을 재사용해요." }
            catch { message = error.localizedDescription }
            failures = await ImportFailureStore.shared.load(name: pack.name)
            if !success, let message { DownloadDiagnostics.shared.record("\(pack.name) · 설치 종료 · \(message)") }
        }
    }
    func downloadBatch() {
        guard !busy, let client else { return }
        guard ImportActivity.shared.count == 0 else { message = "진행 중인 설치·최적화 작업을 먼저 마쳐 주세요."; return }
        let inputs = ([(id: id, value: link)] + additionalLinks.map { (id: $0.id, value: $0.value) })
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
        batchLookupFailures = 0
        downloadSummary = "팩 목록 조회 중"
        let batchUpdating = updating
        busy = true; message = nil; pack = nil; progress = nil
        operation = Task {
            backgroundID = await BackgroundWork.shared.begin(title: restoringOriginal ? "스티커 원본 복원" : (updating ? "스티커 팩 일괄 업데이트" : "스티커 팩 일괄 설치")) { self.cancel() }
            var success = false
            defer { BackgroundWork.shared.end(id: backgroundID, success: success); backgroundID = nil; busy = false }
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
                    success = batchLookupFailures == 0 && batchCounts.values.allSatisfy { $0.failed == 0 } && !batchStatuses.contains { $0.status.hasPrefix("실패") }
                    if success { try await coordinator.saveBatch(BatchImportDraft(origin: client.configuration.origin, links: [], updating: batchUpdating)) }
                    await coordinator.endBatch(directory: directory, completed: success)
                } catch {
                    // The task group has joined all children before releasing
                    // the root lease, including when a user cancels the batch.
                    try? await coordinator.orderBatch(links: links)
                    ImportActivity.shared.libraryChangeID += 1
                    await coordinator.endBatch(directory: directory, completed: false)
                    throw error
                }
                message = "일괄 설치를 마쳤어요. 실패한 팩은 다시 시도하면 돼요."
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
                batchCounts[index] = ImportProgress(completed: remote.stickers.count, total: remote.stickers.count, failed: 0)
            } else {
                batchStatuses[index].status = "다운로드 중"
                let receipt = try await worker.install(remote, client: client, updating: updating, restoringOriginal: restoringOriginal) { value in
                    await self.updateBatchProgress(index: index, value: value)
                }
                batchCounts[index] = ImportProgress(completed: receipt.installed, total: receipt.total, failed: receipt.failed)
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
            failed: min(max(0, value.failed), max(0, value.total - completed)))
        batchStatuses[index].status = "스티커 설치 중"
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
        let value = ImportProgress(completed: completed, total: total, failed: failed)
        downloadSummary = value.displayText
        if batchLookupFailures > 0 { downloadSummary += " · 조회 실패 \(batchLookupFailures)팩" }
        BackgroundWork.shared.report(id: backgroundID, completed: Int64(value.installedCount),
            total: Int64(total), subtitle: downloadSummary)
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
        BackgroundWork.shared.report(id: backgroundID, completed: Int64(value.installedCount), total: Int64(value.total), subtitle: downloadSummary)
    }
    func cancel() { operation?.cancel() }
}

struct ImportView: View {
    @ScaledMetric(relativeTo: .caption) private var stickerWidth = 64
    @State private var model: ImportModel
    @State private var settings = false
    @State private var showLogs = false
    private let initialPackName: String?
    private let updating: Bool
    private let initialLinks: [String]
    private let resumesSession: Bool
    @FocusState private var linkFocused: Bool
    @Environment(\.dismiss) private var dismiss
    init(writer: LibraryWriter, initialPackName: String? = nil, updating: Bool = false, initialLinks: [String] = []) {
        if let current = ImportActivity.shared.current, current.busy {
            _model = State(initialValue: current)
            self.initialPackName = nil; self.updating = current.updating; self.initialLinks = []
            resumesSession = true
        } else {
            _model = State(initialValue: ImportModel(writer: writer))
            self.initialPackName = initialPackName; self.updating = updating; self.initialLinks = initialLinks
            resumesSession = false
        }
    }
    init(model: ImportModel) {
        _model = State(initialValue: model)
        initialPackName = nil; updating = model.updating; initialLinks = []
        resumesSession = true
    }
    // TextField may read/write its binding while SwiftUI is tearing down a deleted row.
    // Resolve by stable ID each time; never retain an array element/index binding.
    private func additionalLinkValue(for entry: AdditionalPackLink) -> Binding<String> {
        let id = entry.id
        return Binding(
            get: { model.additionalLinks.first(where: { $0.id == id })?.value ?? entry.value },
            set: { value in
                guard !model.busy, let index = model.additionalLinks.firstIndex(where: { $0.id == id }) else { return }
                model.additionalLinks[index].value = value
            }
        )
    }

    private func linkInput(_ value: Binding<String>) -> some View {
        TextField("https://t.me/addstickers/…", text: value, axis: .vertical)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            .lineLimit(1...5)
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
                    Text(item.status).font(.caption).foregroundStyle(item.status.hasPrefix("실패") ? .red : .secondary)
                    if let progress = model.itemProgress(id: item.id) {
                        ProgressView(value: progress.fraction)
                        Text(progress.displayText).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 4).padding(.bottom, 8)
            }
        } else if id == model.id, let pack = model.pack {
            VStack(alignment: .leading, spacing: 5) {
                Text(pack.title).font(.subheadline.bold())
                Text("전체 \(pack.stickers.count)개 · 설치 대상 \(pack.installableStickers.count)개").font(.caption).foregroundStyle(.secondary)
                if let progress = model.progress {
                    ProgressView(value: progress.fraction)
                    Text(progress.displayText).font(.caption2.monospacedDigit())
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
                            ProgressView(value: BackgroundWork.shared.fraction)
                        }
                    }
                    Text("Telegram 공개 팩 링크를 추가하세요.").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        linkInput(Binding(get: { model.link }, set: { model.link = $0; model.pack = nil; model.installed = false; model.result = nil }))
                            .accessibilityIdentifier("packLink")
                            .focused($linkFocused).submitLabel(.go)
                            .onSubmit { linkFocused = false; if PackLinkList.split(model.link).count > 1 { model.downloadBatch() } else { model.preview() } }
                        if initialPackName == nil {
                            Button {
                                guard !model.additionalLinks.isEmpty else { return }
                                model.link = model.additionalLinks.removeFirst().value
                                model.pack = nil; model.installed = false; model.result = nil
                            } label: {
                                Image(systemName: "minus.circle").frame(width: 44, height: 44)
                            }
                            .disabled(model.additionalLinks.isEmpty)
                            .accessibilityLabel("링크 삭제")
                        }
                    }.disabled(model.busy)
                    linkStatus(id: model.id, value: model.link)
                    if initialPackName == nil {
                        ForEach(model.additionalLinks) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    linkInput(additionalLinkValue(for: entry))
                                    Button { model.additionalLinks.removeAll { $0.id == entry.id } } label: {
                                        Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                    }.accessibilityLabel("링크 삭제")
                                }.disabled(model.busy)
                                linkStatus(id: entry.id, value: entry.value)
                            }
                        }
                        Button { model.additionalLinks.append(AdditionalPackLink()) } label: {
                            Label("링크 추가", systemImage: "plus.circle")
                        }.buttonStyle(.glass).disabled(model.busy || updating).accessibilityIdentifier("addPackLink")
                        if !model.additionalLinks.isEmpty || PackLinkList.split(model.link).count > 1 || !model.batchStatuses.isEmpty || model.restoringOriginal {
                            Button { linkFocused = false; model.downloadBatch() } label: {
                                Label(model.restoringOriginal ? "입력한 팩 원본 복원" : (updating ? "입력한 팩 모두 업데이트" : "입력한 팩 모두 설치"), systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                            }.buttonStyle(.glassProminent).controlSize(.large)
                                .disabled(model.busy || model.client == nil).accessibilityIdentifier("installBatch")
                            Text("입력한 팩을 동시에 다운로드해요. 한 팩이 실패해도 다른 팩은 계속하고, 이미 설치한 팩과 중복 링크는 건너뛰어요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("다운로드 로그", systemImage: "doc.text.magnifyingglass") { showLogs = true }
                        .buttonStyle(.glass)
                    if model.additionalLinks.isEmpty && PackLinkList.split(model.link).count <= 1 {
                    Button { linkFocused = false; model.preview() } label: {
                        Label("팩 미리보기", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.glass).controlSize(.large)
                        .disabled(model.busy || model.client == nil).accessibilityIdentifier("previewPack")
                    }
                    if let message = model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("importMessage") }
                    if let pack = model.pack, model.additionalLinks.isEmpty && PackLinkList.split(model.link).count <= 1 {
                        if pack.installableStickers.count != pack.stickers.count {
                            Text("마스크·커스텀 이모지 팩은 설치하지 않아요.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { model.download() } label: {
                            Text(updating ? (model.installed ? "업데이트 완료" : "팩 업데이트") : model.result.map { $0.failed > 0 ? "실패한 \($0.failed)개 다시 시도" : "설치 완료" }
                                ?? (model.progress == nil ? "스티커 설치" : "다시 시도")).frame(maxWidth: .infinity)
                        }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .disabled(model.busy || model.installed || (!updating && pack.installableStickers.isEmpty))
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
                            }.accessibilityIdentifier("importFailures")
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.restoringOriginal ? "스티커 원본 복원" : (updating ? "스티커 팩 업데이트" : "Telegram 팩 추가"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.accessibilityIdentifier("closeImport") }
                ToolbarItem(placement: .topBarTrailing) { Button("연결 설정") { settings = true }.disabled(model.busy) }
            }
            .sheet(isPresented: $showLogs) { NavigationStack { DownloadLogsView() } }
            .sheet(isPresented: $settings, onDismiss: { Task { await model.configure() } }) { ImportConnectionView() }
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

private struct RemoteStickerPreview: View {
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

private struct ImportConnectionView: View {
    @State private var address = ""
    @State private var key = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("개인 테스트 서버") {
                    TextField("https://…workers.dev", text: $address).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Worker 테스트 접근키", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Bot Token은 서버 Secret에만 저장합니다. 이 화면에는 별도의 테스트 접근키를 입력하세요. 접근키는 이 기기의 Keychain에만 저장돼요.")
                        .font(.footnote)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("저장") {
                    do {
                        let config = try WorkerConfiguration(address: address, accessKey: key)
                        try ImportSettings.save(config); dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }.navigationTitle("가져오기 연결")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .task {
                    if let config = try? ImportSettings.load() { address = config.origin.absoluteString; key = config.accessKey }
                }
        }
    }
}

struct DownloadLogsView: View {
    var body: some View {
            List {
                if DownloadDiagnostics.shared.entries.isEmpty { Text("아직 기록된 실패·재시도가 없어요.").foregroundStyle(.secondary) }
                ForEach(DownloadDiagnostics.shared.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                        Text(entry.detail).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("다운로드 로그")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("복사") { UIPasteboard.general.string = DownloadDiagnostics.shared.text }
                    Button("비우기", role: .destructive) { DownloadDiagnostics.shared.clear() }
                }
            }
    }
}
