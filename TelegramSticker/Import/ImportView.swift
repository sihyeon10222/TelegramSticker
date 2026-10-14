import SwiftUI
import ImageIO

@MainActor @Observable
final class ImportActivity {
    static let shared = ImportActivity()
    var count = 0
}

struct AdditionalPackLink: Identifiable {
    let id = UUID()
    var value = ""
}
struct BatchPackStatus: Identifiable {
    let id = UUID()
    let link: String
    var title: String
    var status = "대기 중"
}

@MainActor @Observable
final class ImportModel {
    var link = ""
    var additionalLinks: [AdditionalPackLink] = []
    var batchStatuses: [BatchPackStatus] = []
    private var batchFractions: [Double] = []
    var pack: RemotePack?
    var message: String?
    var progress: ImportProgress?
    var busy = false {
        didSet { if oldValue != busy { ImportActivity.shared.count = max(0, ImportActivity.shared.count + (busy ? 1 : -1)) } }
    }
    var installed = false
    var result: ImportResult?
    var client: WorkerClient?
    var failures: [ImportFailure] = []
    var updating = false
    private let coordinator: ImportCoordinator
    private var operation: Task<Void, Never>?
    private var backgroundID: String?
    init(writer: LibraryWriter, root: URL? = nil) { coordinator = ImportCoordinator(writer: writer, root: root) }

    func configure() async {
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
        busy = true; message = nil
        operation = Task {
            backgroundID = await BackgroundWork.shared.begin(title: updating ? "스티커 팩 업데이트" : "스티커 설치") { self.cancel() }
            var success = false
            defer { BackgroundWork.shared.end(id: backgroundID, success: success); backgroundID = nil; busy = false }
            do {
                let receipt = try await coordinator.install(pack, client: client, updating: updating, onlyIDs: onlyIDs) { value in
                    await self.updateProgress(value)
                }
                result = receipt; installed = receipt.failed == 0; message = receipt.message; success = receipt.failed == 0
            } catch is CancellationError { message = "중단했어요. 다시 시도하면 준비된 파일을 재사용해요." }
            catch { message = error.localizedDescription }
            failures = await ImportFailureStore.shared.load(name: pack.name)
        }
    }
    func downloadBatch() {
        guard !busy, let client else { return }
        guard ImportActivity.shared.count == 0 else { message = "진행 중인 설치·최적화 작업을 먼저 마쳐 주세요."; return }
        let links = ([link] + additionalLinks.map(\.value)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !links.isEmpty else { message = "팩 링크를 입력해 주세요."; return }
        batchStatuses = links.map { BatchPackStatus(link: $0, title: $0) }
        batchFractions = Array(repeating: 0, count: links.count)
        let batchUpdating = updating
        busy = true; message = nil; pack = nil; progress = nil
        operation = Task {
            backgroundID = await BackgroundWork.shared.begin(title: updating ? "스티커 팩 일괄 업데이트" : "스티커 팩 일괄 설치") { self.cancel() }
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
                                batchFractions[index] = 1
                            }
                        } catch {
                            batchStatuses[index].status = "실패 · " + error.localizedDescription
                            batchFractions[index] = 1
                        }
                    }
                    reportBatchProgress()
                    // Limit pack work to three. All workers share the client's
                    // three-request gate and the serial animation conversion gate.
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        var next = 0
                        func enqueue() {
                            let item = pending[next]
                            next += 1
                            group.addTask { @MainActor in
                                let worker = try await self.coordinator.batchWorker(directory: directory, name: item.name)
                                try await self.installBatchPack(index: item.index, name: item.name,
                                    client: client, worker: worker, updating: batchUpdating)
                            }
                        }
                        for _ in 0..<min(3, pending.count) { enqueue() }
                        while try await group.next() != nil {
                            try Task.checkCancellation()
                            if next < pending.count { enqueue() }
                        }
                    }
                    try Task.checkCancellation()
                    success = !batchStatuses.contains { $0.status.hasPrefix("실패") || $0.status.contains("개 실패") }
                    if success { try await coordinator.saveBatch(BatchImportDraft(origin: client.configuration.origin, links: [], updating: batchUpdating)) }
                    await coordinator.endBatch(directory: directory, completed: success)
                } catch {
                    // The task group has joined all children before releasing
                    // the root lease, including when a user cancels the batch.
                    await coordinator.endBatch(directory: directory, completed: false)
                    throw error
                }
                message = "일괄 설치를 마쳤어요. 실패한 팩은 다시 시도하면 돼요."
            } catch {
                for index in batchStatuses.indices where batchStatuses[index].status == "대기 중" || batchStatuses[index].status == "다운로드 중" || batchStatuses[index].status == "팩 조회 중" || batchStatuses[index].status.hasPrefix("준비 ") {
                    batchStatuses[index].status = "중단됨 · 다시 시도 가능"
                }
                message = error is CancellationError ? "중단했어요. 설치 완료한 팩은 유지해요." : error.localizedDescription
            }
        }
    }

    private func installBatchPack(index: Int, name: String, client: WorkerClient,
                                  worker: ImportCoordinator, updating: Bool) async throws {
        do {
            try Task.checkCancellation()
            batchStatuses[index].status = "팩 조회 중"
            reportBatchProgress()
            let remote = try await client.pack(name: name, refresh: updating)
            try Task.checkCancellation()
            batchStatuses[index].title = remote.title
            if !updating, let installed = try await worker.installedResult(for: remote), installed.failed == 0 {
                batchStatuses[index].status = "이미 설치됨 · 건너뜀"
            } else {
                batchStatuses[index].status = "다운로드 중"
                let receipt = try await worker.install(remote, client: client, updating: updating) { value in
                    await self.updateBatchProgress(index: index, value: value)
                }
                batchStatuses[index].status = receipt.failed == 0 ? "\(receipt.installed)개 설치 완료" : "\(receipt.installed)개 설치 · \(receipt.failed)개 실패 (다시 시도 가능)"
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            batchStatuses[index].status = "실패 · " + error.localizedDescription
        }
        batchFractions[index] = 1
        reportBatchProgress()
    }

    private func updateBatchProgress(index: Int, value: ImportProgress) {
        // Leave the final five percent for publishing the installed pack.
        let fraction = min(0.95, Double(value.completed + value.failed) / Double(max(1, value.total)) * 0.95)
        batchFractions[index] = max(batchFractions[index], fraction)
        batchStatuses[index].status = "준비 \(value.completed)/\(value.total) · 실패 \(value.failed)"
        reportBatchProgress()
    }

    private func reportBatchProgress() {
        let finished = batchFractions.filter { $0 == 1 }.count
        let active = batchStatuses.filter { $0.status == "팩 조회 중" || $0.status == "다운로드 중" || $0.status.hasPrefix("준비 ") }.count
        BackgroundWork.shared.report(id: backgroundID,
            completed: Int64(batchFractions.reduce(0, +) * 1000),
            total: Int64(batchFractions.count * 1000),
            subtitle: "팩 \(finished)/\(batchFractions.count) 완료 · \(active)개 동시 처리 중")
    }
    private func loadInstalledStatus(_ pack: RemotePack) async throws {
        result = try await coordinator.installedResult(for: pack)
        installed = !updating && result?.failed == 0
    }
    private func updateProgress(_ value: ImportProgress) {
        progress = value
        BackgroundWork.shared.report(id: backgroundID, completed: Int64(value.completed + value.failed), total: Int64(value.total + 1), subtitle: "준비 \(value.completed)/\(value.total) · 실패 \(value.failed)")
    }
    func cancel() { operation?.cancel() }
}

struct ImportView: View {
    @ScaledMetric(relativeTo: .caption) private var stickerWidth = 64
    @State private var model: ImportModel
    @State private var settings = false
    private let initialPackName: String?
    private let updating: Bool
    private let initialLinks: [String]
    @FocusState private var linkFocused: Bool
    @Environment(\.dismiss) private var dismiss
    init(writer: LibraryWriter, initialPackName: String? = nil, updating: Bool = false, initialLinks: [String] = []) {
        _model = State(initialValue: ImportModel(writer: writer)); self.initialPackName = initialPackName; self.updating = updating; self.initialLinks = initialLinks
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.pack == nil {
                        Text("Telegram 공개 팩 링크를 추가하세요.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    TextField("https://t.me/addstickers/…", text: Binding(get: { model.link }, set: { model.link = $0; model.pack = nil; model.installed = false; model.result = nil }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .textFieldStyle(.plain).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Color(uiColor: .tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("packLink")
                        .disabled(model.busy)
                        .focused($linkFocused).submitLabel(.go)
                        .onSubmit { linkFocused = false; model.preview() }
                    if !updating && initialPackName == nil {
                        ForEach($model.additionalLinks) { $entry in
                            HStack {
                                TextField("https://t.me/addstickers/…", text: $entry.value)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                    .padding(12).background(Color(uiColor: .tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                                Button { model.additionalLinks.removeAll { $0.id == entry.id } } label: {
                                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                }.accessibilityLabel("링크 삭제")
                            }.disabled(model.busy)
                        }
                        Button { model.additionalLinks.append(AdditionalPackLink()) } label: {
                            Label("링크 추가", systemImage: "plus.circle")
                        }.disabled(model.busy).accessibilityIdentifier("addPackLink")
                        if !model.additionalLinks.isEmpty {
                            Button { linkFocused = false; model.downloadBatch() } label: {
                                Label("입력한 팩 모두 설치", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                            }.buttonStyle(.glassProminent).controlSize(.large)
                                .disabled(model.busy || model.client == nil).accessibilityIdentifier("installBatch")
                            Text("최대 3개 팩을 동시에 설치해요. 한 팩이 실패해도 다른 팩은 계속하고, 이미 설치한 팩과 중복 링크는 건너뛰어요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(model.batchStatuses) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.bold()).lineLimit(2)
                            Text(item.status).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if model.additionalLinks.isEmpty {
                    Button { linkFocused = false; model.preview() } label: {
                        Label("팩 미리보기", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.glass).controlSize(.large)
                        .disabled(model.busy || model.client == nil).accessibilityIdentifier("previewPack")
                    }
                    if let message = model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("importMessage") }
                    if let pack = model.pack, model.additionalLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pack.title).font(.title3.bold())
                            Text("전체 \(pack.stickers.count)개 · 설치 대상 \(pack.installableStickers.count)개")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if pack.installableStickers.count != pack.stickers.count {
                            Text("마스크·커스텀 이모지 팩은 설치하지 않아요.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let progress = model.progress {
                            ProgressView(value: Double(progress.completed + progress.failed), total: Double(max(1, progress.total)))
                            Text("준비 \(progress.completed)/\(progress.total) · 실패 \(progress.failed)").font(.caption)
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
            .navigationTitle(updating ? "스티커 팩 업데이트" : "Telegram 팩 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.accessibilityIdentifier("closeImport") }
                ToolbarItem(placement: .topBarTrailing) { Button("연결 설정") { settings = true }.disabled(model.busy) }
            }
            .sheet(isPresented: $settings, onDismiss: { Task { await model.configure() } }) { ImportConnectionView() }
            .task {
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
