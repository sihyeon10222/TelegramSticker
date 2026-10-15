import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor @Observable
final class OptimizationSession: Identifiable {
    let id = UUID()
    let request: OptimizationRequest
    var profile = StorageOptimizationProfile.compact
    var running = false
    var applying = false
    var finished = false
    var message: String?
    var progress = 0.0
    var zoom = 1.0
    var restoreImport: ImportModel?
    var sourceLinks: [String] = []
    private var drafts: [StorageOptimizationProfile: PreparedOptimization] = [:]
    private var operation: Task<Void, Never>?
    private var progressGeneration = UUID()
    var draft: PreparedOptimization? { drafts[profile] }
    private var jobs: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportJobs") }
    init(request: OptimizationRequest) {
        self.request = request
        if let reader = try? LibraryReader.shared(), let snapshot = try? reader.snapshot(resolvingFiles: false) {
            sourceLinks = snapshot.packs.filter { request.packIDs == nil || request.packIDs!.contains($0.id) }
                .compactMap { $0.telegramName.map { "https://t.me/addstickers/" + $0 } }
        }
    }
    func removeDrafts(deleteFiles: Bool = true) {
        guard !running else { return }
        let roots = drafts.values.map(\.root)
        drafts.removeAll()
        if deleteFiles { Self.discard(roots) }
    }
    func selectProfile() {
        guard !running, !finished else { return }
        message = nil
        guard let cached = draft, let writer = LibraryWriter.shared else { return }
        let selected = profile
        Task {
            for original in cached.originals {
                if (try? await writer.hasRevision(id: original.id, revision: original.revision)) != true {
                    // Only invalidate the stale profile, keeping the other cached result.
                    if drafts[selected]?.root == cached.root {
                        drafts.removeValue(forKey: selected)
                        Self.discard([cached.root])
                    }
                    if profile == selected { message = "팩이 변경되어 이 비교 버전을 다시 만들어야 해요." }
                    return
                }
            }
        }
    }
    private static func discard(_ roots: [URL]) {
        Task.detached(priority: .utility) {
            for root in roots { try? FileManager.default.removeItem(at: root) }
        }
    }
    func cancel() { operation?.cancel() }
    func start(apply: Bool) {
        guard !running, ImportActivity.shared.count == 0 else { return }
        if !apply, draft != nil { return }
        guard !apply || draft != nil else { return }
        let selectedProfile = profile
        let selectedDraft = draft
        running = true; applying = apply; progress = 0; message = nil
        let generation = UUID(); progressGeneration = generation
        ImportActivity.shared.count += 1
        operation = Task {
            await DownloadDiagnostics.shared.run(title: apply ? "용량 최적화 적용" : "용량 최적화 비교 준비") {
                let id = await BackgroundWork.shared.begin(kind: apply ? .optimizationApply : .optimizationPreparation, title: apply ? "스티커 용량 최적화 적용" : "스티커 용량 최적화 비교 준비") { self.cancel() }
                var success = false
                defer {
                    running = false; ImportActivity.shared.count -= 1
                    BackgroundWork.shared.end(id: id, success: success, detail: message, cancelled: Task.isCancelled)
                }
                do {
                    guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                    let report: @Sendable (Int, Int) -> Void = { done, total in
                        Task { @MainActor in
                            guard self.running, self.progressGeneration == generation else { return }
                            self.progress = min(0.99, Double(done) / Double(max(1, total)))
                            BackgroundWork.shared.report(id: id, completed: Int64(done), total: Int64(max(1, total)), subtitle: "처리 \(done)/\(total) · \(Int(self.progress * 100))%")
                        }
                    }
                    if apply, let selectedDraft {
                        let result = try await ImportJobCache.shared.applyOptimization(root: jobs, writer: writer, draft: selectedDraft, progress: report)
                        success = result.failures.isEmpty; finished = true; progress = success ? 1 : min(progress, 0.99)
                        ImportActivity.shared.libraryChangeID += 1
                        message = "\(result.optimizedPacks)개 팩 반영 · \(ByteCountFormatter.string(fromByteCount: result.saved, countStyle: .file)) 절약" + (result.failures.isEmpty ? "" : "\n" + result.failures.joined(separator: "\n"))
                        // The source revisions changed; other profiles must not overwrite them.
                        let obsolete = drafts.filter { $0.key != selectedProfile }.values.map(\.root)
                        drafts = [selectedProfile: selectedDraft]
                        Self.discard(obsolete)
                    } else {
                        let prepared = try await ImportJobCache.shared.prepareOptimization(root: jobs, writer: writer,
                            packIDs: request.packIDs, stickerIDs: request.stickerIDs, profile: selectedProfile, progress: report)
                        drafts[selectedProfile] = prepared
                        success = true; progress = 1
                        if prepared.saved == 0 { message = "현재 품질에서는 더 줄일 용량이 없어요. 원본을 유지해요." }
                    }
                    progressGeneration = UUID()
                    if success { BackgroundWork.shared.report(id: id, completed: 1, total: 1, subtitle: apply ? "용량 최적화 적용 완료 · 100%" : "비교 준비 완료 · 100%", finalized: true) }
                } catch {
                    progressGeneration = UUID()
                    message = error is CancellationError ? "중단했어요. 완료된 팩은 유지하고, 처리 중인 팩의 기존 파일은 보존해요." : error.localizedDescription
                }
            }
        }
    }
    func newComparison() { removeDrafts(); finished = false; message = nil; progress = 0 }
    func restoreOriginals() {
        guard !running, ImportActivity.shared.count == 0, !sourceLinks.isEmpty, let writer = LibraryWriter.shared else { return }
        operation = Task {
            let model = ImportModel(writer: writer)
            model.updating = true
            model.restoringOriginal = true
            await model.configure()
            guard ImportActivity.shared.count == 0 else { return }
            model.link = sourceLinks[0]
            model.additionalLinks = sourceLinks.dropFirst().map { var entry = AdditionalPackLink(); entry.value = $0; return entry }
            restoreImport = model
        }
    }
}
