import Foundation
import Observation

nonisolated enum PackUpdateScope: String, Codable, Sendable {
    case all, additions, deletions, changes
}

nonisolated struct PackUpdateDifference: Sendable {
    let added: [RemoteSticker]
    let removed: [StickerRecord]
    let changed: [RemoteSticker]
    let recovery: [RemoteSticker]
    let titleChanged: Bool
    let orderChanged: Bool
    let countChanged: Bool

    init(installed: PackManifestV1, remote: RemotePack) {
        let old = Dictionary(uniqueKeysWithValues: installed.stickers.map { ($0.id, $0) })
        let oldPositions = Dictionary(uniqueKeysWithValues: installed.stickers.enumerated().map { ($0.element.id, $0.offset) })
        let pending = Set(installed.pendingStickerIDs ?? [])
        let remoteIDs = Set(remote.stickers.map(\.id))
        added = remote.stickers.filter { old[$0.id] == nil && !pending.contains($0.id) }
        recovery = remote.stickers.filter { old[$0.id] == nil && pending.contains($0.id) }
        removed = installed.stickers.filter { !remoteIDs.contains($0.id) }
        changed = remote.stickers.filter { sticker in
            guard let record = old[sticker.id] else { return false }
            let previousDefault = "스티커 \((oldPositions[sticker.id] ?? 0) + 1)"
            return record.sourceFormat != sticker.format || record.name != (sticker.emoji ?? previousDefault)
        }
        titleChanged = installed.title != remote.title
        orderChanged = installed.stickers.filter { remoteIDs.contains($0.id) }.map(\.id)
            != remote.stickers.filter { old[$0.id] != nil }.map(\.id)
        countChanged = installed.originalCount != remote.stickers.count
    }

    var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty || !changed.isEmpty || !recovery.isEmpty || titleChanged || orderChanged || countChanged
    }
    func hasChanges(in scope: PackUpdateScope) -> Bool {
        switch scope {
        case .all: hasChanges
        case .additions: !added.isEmpty || !recovery.isEmpty
        case .deletions: !removed.isEmpty
        case .changes: !changed.isEmpty || titleChanged || orderChanged
        }
    }
    var summary: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("추가 \(added.count)개") }
        if !removed.isEmpty { parts.append("삭제 \(removed.count)개") }
        if !changed.isEmpty { parts.append("변경 \(changed.count)개") }
        if !recovery.isEmpty { parts.append("미설치 항목 복구 \(recovery.count)개") }
        if titleChanged { parts.append("팩 이름 변경") }
        if orderChanged { parts.append("순서 변경") }
        return parts.isEmpty ? (hasChanges ? "팩 정보 변경" : "업데이트할 내용이 없어요") : parts.joined(separator: " · ")
    }
}

nonisolated struct PackUpdateEntry: Identifiable, Sendable {
    var id: String { installed.id }
    let installed: PackManifestV1
    let remote: RemotePack
    let checkedAt: Date
    let difference: PackUpdateDifference
    init(installed: PackManifestV1, remote: RemotePack, checkedAt: Date) {
        self.installed = installed; self.remote = remote; self.checkedAt = checkedAt
        difference = PackUpdateDifference(installed: installed, remote: remote)
    }
}

private actor PackUpdateCache {
    private struct Record: Codable { let remote: RemotePack; let checkedAt: Date }
    private let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PackUpdateChecks", isDirectory: true)

    func load(packs: [PackManifestV1]) -> [PackUpdateEntry] {
        packs.compactMap { pack in
            guard let name = pack.telegramName, StickerLink.validName(name) else { return nil }
            let file = root.appendingPathComponent(name + ".json")
            guard file.resolvingSymlinksInPath().path == file.path,
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024,
                  let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data),
                  (try? record.remote.validate(requestedName: name)) != nil,
                  record.remote.refreshed == true, record.checkedAt.timeIntervalSince1970.isFinite else { return nil }
            return PackUpdateEntry(installed: pack, remote: record.remote, checkedAt: record.checkedAt)
        }
    }
    func save(_ entry: PackUpdateEntry) throws {
        guard StickerLink.validName(entry.remote.name), root.resolvingSymlinksInPath().path == root.path else { throw LibraryError.unsafePath }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(entry.remote.name + ".json")
        guard file.resolvingSymlinksInPath().path == file.path else { throw LibraryError.unsafePath }
        try JSONEncoder().encode(Record(remote: entry.remote, checkedAt: entry.checkedAt)).write(to: file, options: .atomic)
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
    func remove(name: String) throws {
        guard StickerLink.validName(name) else { throw LibraryError.unsafePath }
        let file = root.appendingPathComponent(name + ".json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

/// App-only metadata checks. No installed files are validated, converted or published here.
@MainActor @Observable
final class PackUpdateService {
    static let shared = PackUpdateService()
    private(set) var entries: [String: PackUpdateEntry] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var checking = Set<String>()
    private(set) var isChecking = false
    private(set) var status: String?
    @ObservationIgnored private let cache = PackUpdateCache()
    private struct Request { let id: UUID; let task: Task<RemotePack, Error> }
    @ObservationIgnored private var requests: [String: Request] = [:]
    private struct Scan { let ids: Set<String>; let task: Task<Void, Never>; var notify: Bool }
    @ObservationIgnored private var scans: [UUID: Scan] = [:]
    @ObservationIgnored private var primaryScanID: UUID?
    @ObservationIgnored private var client: WorkerClient?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var resetting = false
    @ObservationIgnored private var installedPacks: [String: PackManifestV1] = [:]
    @ObservationIgnored private var hasSnapshot = false
    @ObservationIgnored private var localDeletionGenerations: [String: Int] = [:]
    @ObservationIgnored private var invalidatedChecks = Set<String>()

    /// Local edits invalidate a previous check; only a new explicit check may restore it.
    func didDeleteStickers(packID: String, telegramName: String?) async {
        localDeletionGenerations[packID, default: 0] += 1
        invalidatedChecks.insert(packID)
        entries[packID] = nil
        errors[packID] = nil
        if let telegramName {
            do { try await cache.remove(name: telegramName) }
            catch { DownloadDiagnostics.shared.record("업데이트 조회 결과 제거 실패 · " + error.localizedDescription) }
        }
    }

    var updates: [PackUpdateEntry] { entries.values.filter { $0.difference.hasChanges }.sorted { $0.installed.title < $1.installed.title } }

    func restore(packs: [PackManifestV1]) async {
        let generation = generation
        reconcile(packs: packs)
        let saved = await cache.load(packs: packs)
        guard generation == self.generation else { return }
        for entry in saved where entries[entry.id] == nil && !invalidatedChecks.contains(entry.id) {
            if let current = installedPacks[entry.id], current.telegramName == entry.remote.name {
                entries[entry.id] = PackUpdateEntry(installed: current, remote: entry.remote, checkedAt: entry.checkedAt)
            }
        }
    }

    func reconcile(packs: [PackManifestV1]) {
        let current = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0) })
        installedPacks = current
        hasSnapshot = true
        entries = entries.compactMapValues { entry in
            guard let pack = current[entry.id], pack.telegramName == entry.remote.name else { return nil }
            if pack.revision == entry.installed.revision { return entry }
            return PackUpdateEntry(installed: pack, remote: entry.remote, checkedAt: entry.checkedAt)
        }
        errors = errors.filter { current[$0.key] != nil }
        if !isChecking, updates.isEmpty, status?.hasPrefix("업데이트할 팩") == true {
            status = errors.isEmpty ? "업데이트할 내용이 없어요." : "일부 팩을 확인하지 못했어요."
        }
    }

    /// Imports/restores may fetch newer metadata without opening the review screen.
    /// Keep a newer check if an older, already reviewed version was applied meanwhile.
    func didInstall(remote: RemotePack, installed: PackManifestV1) async {
        installedPacks[installed.id] = installed
        errors[installed.id] = nil
        let fetchedAt = remote.fetchedAt.map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        let entry: PackUpdateEntry?
        if let newer = entries[installed.id], newer.checkedAt > fetchedAt {
            entry = PackUpdateEntry(installed: installed, remote: newer.remote, checkedAt: newer.checkedAt)
        } else if remote.refreshed == true {
            entry = PackUpdateEntry(installed: installed, remote: remote, checkedAt: fetchedAt)
        } else { entry = nil }
        entries[installed.id] = entry
        do {
            if let entry { try await cache.save(entry) }
            else { try await cache.remove(name: remote.name) }
        } catch { DownloadDiagnostics.shared.record("업데이트 조회 결과 저장 실패 · " + error.localizedDescription) }
        if !isChecking, status != nil {
            status = updates.isEmpty ? "업데이트할 내용이 없어요." : "업데이트할 팩이 \(updates.count)개 있어요."
            if !errors.isEmpty { status = (status ?? "") + " · 조회 실패 \(errors.count)팩" }
        }
    }

    func check(_ pack: PackManifestV1, using suppliedClient: WorkerClient? = nil) async throws -> PackUpdateEntry {
        try Task.checkCancellation()
        guard !resetting else { throw CancellationError() }
        let generation = generation
        let deletionGeneration = localDeletionGenerations[pack.id, default: 0]
        guard let name = pack.telegramName else {
            errors[pack.id] = StickerImportError.invalidLink.localizedDescription
            throw StickerImportError.invalidLink
        }
        let request: Request
        if let pending = requests[name] { request = pending }
        else {
            let connection: WorkerClient
            do {
                if let suppliedClient { connection = suppliedClient }
                else if let client { connection = client }
                else {
                    guard let configuration = try ImportSettings.load() else { throw StickerImportError.invalidConfiguration }
                    connection = WorkerClient(configuration: configuration)
                    client = connection
                }
            } catch {
                errors[pack.id] = error.localizedDescription
                throw error
            }
            request = Request(id: UUID(), task: Task { try await connection.pack(name: name, refresh: true) })
            requests[name] = request
        }
        checking.insert(pack.id)
        errors[pack.id] = nil
        defer {
            if requests[name]?.id == request.id { requests[name] = nil; checking.remove(pack.id) }
        }
        do {
            let remote = try await request.task.value
            try Task.checkCancellation()
            guard self.generation == generation, localDeletionGenerations[pack.id, default: 0] == deletionGeneration else { throw CancellationError() }
            guard remote.stickerType == "regular" else { throw StickerImportError.noStaticStickers }
            if hasSnapshot, installedPacks[pack.id]?.telegramName != name { throw CancellationError() }
            let entry = PackUpdateEntry(installed: installedPacks[pack.id] ?? pack, remote: remote,
                checkedAt: remote.fetchedAt.map(Date.init(timeIntervalSince1970:)) ?? Date())
            if requests[name]?.id == request.id {
                invalidatedChecks.remove(pack.id)
                entries[pack.id] = entry
                errors[pack.id] = nil
                do { try await cache.save(entry) }
                catch { DownloadDiagnostics.shared.record("업데이트 조회 결과 저장 실패 · " + error.localizedDescription) }
            }
            return entry
        } catch {
            if !(error is CancellationError), requests[name]?.id == request.id { errors[pack.id] = error.localizedDescription }
            throw error
        }
    }

    /// An unstructured task keeps a user-started scan alive after its initiating view disappears.
    func check(packs: [PackManifestV1], notify: Bool = false) async {
        guard !resetting else { return }
        let candidates = packs.filter { $0.telegramName != nil }
        let ids = Set(candidates.map(\.id))
        if let running = scans.first(where: { $0.value.ids == ids }) {
            if notify { scans[running.key]?.notify = true }
            await running.value.task.value
            return
        }
        guard !candidates.isEmpty else { status = "확인할 Telegram 팩이 없어요."; return }
        let scanID = UUID()
        if primaryScanID == nil { primaryScanID = scanID }
        isChecking = true
        if primaryScanID == scanID { status = "업데이트 확인 0/\(candidates.count)팩" }
        let task = Task {
            await DownloadDiagnostics.shared.run(title: "스티커 팩 업데이트 확인") {
                let background = await BackgroundWork.shared.begin(kind: .updateCheck, title: "스티커 팩 업데이트 확인") { self.cancel() }
                var done = 0
                await withTaskGroup(of: Void.self) { group in
                    for pack in candidates {
                        group.addTask { @MainActor in
                            do { _ = try await self.check(pack) }
                            catch {
                                if !(error is CancellationError), !Task.isCancelled {
                                    DownloadDiagnostics.shared.record("업데이트 조회 실패 · \(pack.telegramName ?? pack.id) · " + error.localizedDescription)
                                }
                            }
                        }
                    }
                    for await _ in group {
                        done += 1
                        let progress = "업데이트 확인 \(done)/\(candidates.count)팩"
                        if primaryScanID == scanID { status = progress }
                        BackgroundWork.shared.report(id: background, completed: Int64(done), total: Int64(candidates.count), subtitle: progress)
                    }
                }
                let available = updates.filter { ids.contains($0.id) && errors[$0.id] == nil }.count
                let failed = errors.keys.filter { ids.contains($0) }.count
                var completion = Task.isCancelled ? "업데이트 확인을 중단했어요." :
                    (available > 0 ? "업데이트할 팩이 \(available)개 있어요." : (failed == 0 ? "업데이트할 내용이 없어요." : "일부 팩을 확인하지 못했어요."))
                if failed > 0 { completion += " · 조회 실패 \(failed)팩" }
                if primaryScanID == scanID { status = completion }
                if scans[scanID]?.notify == true, available > 0, !Task.isCancelled {
                    await WorkNotifications.shared.requestAuthorizationIfNeeded()
                    if !Task.isCancelled {
                        await WorkNotifications.shared.deliver(title: "스티커 팩 업데이트", body: "업데이트할 팩이 \(available)개 있어요.",
                            identifier: "packUpdates", userInfo: ["packUpdates": "true"])
                    }
                }
                BackgroundWork.shared.end(id: background, success: failed == 0, detail: completion, cancelled: Task.isCancelled)
            }
            scans[scanID] = nil
            if primaryScanID == scanID { primaryScanID = scans.keys.first }
            isChecking = !scans.isEmpty
            if isChecking, primaryScanID != nil { status = "업데이트 확인 중" }
        }
        scans[scanID] = Scan(ids: ids, task: task, notify: notify)
        await task.value
    }

    func cancel() {
        for scan in scans.values { scan.task.cancel() }
        for request in requests.values { request.task.cancel() }
    }

    func reset() async throws {
        resetting = true
        defer { resetting = false }
        generation = UUID()
        cancel()
        let tasks = scans.values.map(\.task)
        for task in tasks { await task.value }
        requests.removeAll(); checking.removeAll(); entries.removeAll(); errors.removeAll(); status = nil; client = nil
        installedPacks.removeAll(); hasSnapshot = false
        localDeletionGenerations.removeAll(); invalidatedChecks.removeAll()
        try await cache.clear()
    }
}
