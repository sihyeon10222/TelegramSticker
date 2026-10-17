import Foundation
import Observation

struct SyncDownloadItem: Identifiable {
    let id: String
    let title: String
    let status: String
    let failed: Bool
}

/// Connects cloud membership to the existing import pipeline without linking imports into the keyboard.
@MainActor @Observable
final class SyncDownloadCoordinator {
    static let shared = SyncDownloadCoordinator()
    private(set) var pendingPacks: [SyncDownloadItem] = []
    private var statuses: [String: (String, Bool)] = [:]
    private var operation: Task<Void, Never>?
    private var download: Task<ImportResult, Error>?
    private var downloadingID: String?
    private var needsAnotherPass = false
    private var attempted = Set<String>()
    private var lastScope: String?
    private var backgroundID: String?

    func reconcile(retryFailures: Bool = false) {
        let sync = LibrarySyncService.shared
        guard sync.enabled, LibraryChangeJournal.cloudKitConfigured else {
            operation?.cancel(); download?.cancel(); pendingPacks = []
            return
        }
        if lastScope != LibraryChangeJournal.scope {
            lastScope = LibraryChangeJournal.scope
            attempted.removeAll(); statuses = [:]
        }
        let active = Set(sync.desiredPacks.map(\.id))
        if let downloadingID, !active.contains(downloadingID) { download?.cancel() }
        ImportActivity.shared.current?.cancelIfImporting(packIDs: sync.deletedPackIDs)
        if retryFailures { attempted.removeAll(); statuses = [:] }
        needsAnotherPass = true
        guard operation == nil else { return }
        operation = Task {
            defer {
                operation = nil
                if needsAnotherPass { reconcile() }
            }
            while needsAnotherPass && !Task.isCancelled {
                needsAnotherPass = false
                await applyDesired()
            }
        }
    }

    private func applyDesired() async {
        let sync = LibrarySyncService.shared
        guard let writer = LibraryWriter.shared, let reader = try? LibraryReader.shared() else { return }
        do {
            // A deletion cancels a matching import first; publication is serialized by LibraryWriter.
            while ImportActivity.shared.count > 0 {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(250))
            }
            for id in sync.deletedPackIDs {
                try Task.checkCancellation()
                try await writer.delete(id: id, syncOrigin: true)
            }
            let snapshot = try reader.snapshot(resolvingFiles: false)
            let installed = Set(snapshot.packs.filter {
                ($0.pendingStickerIDs?.isEmpty != false) || !FileManager.default.fileExists(atPath: self.downloadRoot($0.id).path)
            }.map(\.id))
            publishPending(installed: installed)
            for pack in sync.desiredPacks where !installed.contains(pack.id) && !attempted.contains(pack.id) {
                try Task.checkCancellation()
                guard sync.enabled, sync.desiredPacks.contains(where: { $0.id == pack.id }) else { continue }
                // User-initiated imports/optimization keep priority.
                if ImportActivity.shared.count > 0 { needsAnotherPass = true; break }
                attempted.insert(pack.id)
                downloadingID = pack.id
                statuses[pack.id] = ("준비 중", false)
                publishPending(installed: Set(try reader.index().packs.map(\.id)))
                ImportActivity.shared.count += 1
                let task = Task<ImportResult, Error> {
                    defer { ImportActivity.shared.count = max(0, ImportActivity.shared.count - 1) }
                    await GalleryPreviewStore.shared.cancelForForegroundWork()
                    let root = self.downloadRoot(pack.id)
                    let coordinator = ImportCoordinator(writer: writer, root: root, syncOrigin: true)
                    guard let configuration = try ImportSettings.load() else { throw StickerImportError.invalidConfiguration }
                    let client = WorkerClient(configuration: configuration)
                    self.backgroundID = await BackgroundWork.shared.begin(kind: .download, title: "iCloud 팩 설치 · " + pack.title) { self.download?.cancel() }
                    var success = false
                    defer {
                        BackgroundWork.shared.end(id: self.backgroundID, success: success, cancelled: Task.isCancelled)
                        self.backgroundID = nil
                    }
                    let remote = try await client.pack(name: pack.telegramName)
                    try Task.checkCancellation()
                    let result = try await coordinator.install(remote, client: client) { progress in
                        await self.report(packID: pack.id, progress: progress)
                    }
                    success = result.failed == 0
                    return result
                }
                download = task
                do {
                    let result = try await task.value
                    if result.failed > 0 { statuses[pack.id] = ("일부 설치 실패 · 다시 시도", true) }
                    else { statuses.removeValue(forKey: pack.id); try? FileManager.default.removeItem(at: downloadRoot(pack.id)) }
                } catch is CancellationError {
                    statuses[pack.id] = ("중단됨 · 다시 시도", true)
                } catch { statuses[pack.id] = ("실패 · " + error.localizedDescription, true) }
                download = nil; downloadingID = nil
                ImportActivity.shared.libraryChangeID += 1
                publishPending(installed: Set(try reader.index().packs.map(\.id)))
                // Re-read remote deletion after awaiting network/conversion.
                if sync.deletedPackIDs.contains(pack.id) { try await writer.delete(id: pack.id, syncOrigin: true) }
            }
            try Task.checkCancellation()
            let current = try reader.index().packs.map(\.id)
            let desired = sync.desiredPacks.map(\.id)
            let order = desired.filter { current.contains($0) } + current.filter { !desired.contains($0) }
            if current != order { try await writer.reorder(ids: order, syncOrigin: true) }
            publishPending(installed: Set(try reader.index().packs.map(\.id)))
            ImportActivity.shared.libraryChangeID += 1
        } catch is CancellationError { }
        catch {
            for pack in sync.desiredPacks where statuses[pack.id] == nil { statuses[pack.id] = (error.localizedDescription, true) }
        }
    }
    private func report(packID: String, progress: ImportProgress) {
        statuses[packID] = (progress.displayText, false)
        BackgroundWork.shared.report(id: backgroundID, completed: Int64(progress.installedCount), total: Int64(progress.total), subtitle: progress.displayText)
        publishPending(installed: Set((try? LibraryReader.shared().index().packs.map(\.id)) ?? []))
    }
    private func downloadRoot(_ id: String) -> URL {
        LibraryChangeJournal.root.appendingPathComponent("Downloads/" + LibraryChangeJournal.scope + "/" + id, isDirectory: true)
    }
    private func publishPending(installed: Set<String>) {
        let snapshot = try? LibraryReader.shared().snapshot(resolvingFiles: false)
        let partialIDs = Set((snapshot?.packs ?? []).filter { $0.pendingStickerIDs?.isEmpty == false }.map(\.id))
        pendingPacks = LibrarySyncService.shared.desiredPacks.compactMap { pack in
            let state = statuses[pack.id]
            let partial = partialIDs.contains(pack.id) && FileManager.default.fileExists(atPath: downloadRoot(pack.id).path)
            guard !installed.contains(pack.id) || state?.1 == true || partial else { return nil }
            return SyncDownloadItem(id: pack.id, title: pack.title, status: state?.0 ?? (partial ? "일부 설치 실패 · 다시 시도" : "다운로드 대기 중"), failed: state?.1 ?? partial)
        }
    }
}
