import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

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
            await DownloadDiagnostics.shared.run(title: "팩 미리보기 · \(link)") {
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
                catch { message = error.localizedDescription; DownloadDiagnostics.shared.record("FAIL " + DownloadDiagnostics.errorDetails(error)) }
            }
        }
    }
    func download(onlyIDs: Set<String>? = nil) {
        guard !busy, let client, let pack else { return }
        guard ImportActivity.shared.count == 0 else { message = "진행 중인 설치·용량 최적화 작업을 먼저 마쳐 주세요."; return }
        busy = true; message = nil; downloadSummary = "준비 중"
        operation = Task {
            await DownloadDiagnostics.shared.run(title: (restoringOriginal ? "원본 복원" : updating ? "팩 업데이트" : "팩 다운로드") + " · " + pack.name) {
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
                catch { message = error.localizedDescription; DownloadDiagnostics.shared.record("FAIL " + DownloadDiagnostics.errorDetails(error)) }
                failures = await ImportFailureStore.shared.load(name: pack.name)
                if !success, let message { DownloadDiagnostics.shared.record("\(pack.name) · 설치 종료 · \(message)") }
            }
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
            await DownloadDiagnostics.shared.run(title: restoringOriginal ? "원본 일괄 복원" : updating ? "팩 일괄 업데이트" : "팩 일괄 다운로드") {
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
            DownloadDiagnostics.shared.record("FAIL pack=\(name) stage=metadata " + DownloadDiagnostics.errorDetails(error))
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
            DownloadDiagnostics.shared.record("FAIL pack=\(remote.name) stage=install " + DownloadDiagnostics.errorDetails(error))
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
