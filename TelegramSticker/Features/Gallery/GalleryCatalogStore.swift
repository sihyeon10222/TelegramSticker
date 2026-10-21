import Foundation
import Observation
import CryptoKit

@MainActor @Observable
final class GalleryCatalogStore {
    static let shared = GalleryCatalogStore()
    private(set) var packs = GalleryCatalog.packs
    private(set) var notice: String?
    private(set) var refreshing = false
    private var lastAttempt = Date.distantPast
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gallery/catalog-v1.json")
    }
    private var restoreTask: Task<Void, Never>?
    private var restored = false
    private init() {}

    func restore() async {
        guard !restored else { return }
        if let restoreTask { await restoreTask.value; return }
        let file = Self.file
        let task = Task {
            defer { restoreTask = nil }
            let catalog = await Task.detached(priority: .userInitiated) { () -> RemoteGallery? in
                guard let data = try? Data(contentsOf: file), data.count <= 65536,
                      let catalog = try? JSONDecoder().decode(RemoteGallery.self, from: data),
                      (try? catalog.validate()) != nil else { return nil }
                return catalog
            }.value
            guard !Task.isCancelled else { return }
            if let catalog { apply(catalog) }
            restored = true
        }
        restoreTask = task
        await task.value
    }
    private func apply(_ catalog: RemoteGallery) {
        packs = catalog.packs.map { GalleryRecommendation(id: $0.name, title: $0.name, symbol: "face.smiling") }
    }
    func refresh(client: WorkerClient, force: Bool = false) async {
        guard !refreshing, force || Date().timeIntervalSince(lastAttempt) >= 60 else { return }
        refreshing = true; lastAttempt = Date()
        defer { refreshing = false }
        do {
            let catalog = try await client.gallery()
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(catalog).write(to: Self.file, options: .atomic)
            apply(catalog); notice = nil
        } catch is CancellationError { lastAttempt = .distantPast }
        catch {
            notice = "추천 목록을 갱신하지 못했어요. 저장된 목록을 표시해요."
            DownloadDiagnostics.shared.record("GALLERY_CATALOG " + DownloadDiagnostics.errorDetails(error))
        }
    }
    func reset() { restoreTask?.cancel(); restoreTask = nil; restored = true; packs = GalleryCatalog.packs; notice = nil; lastAttempt = .distantPast }
}
