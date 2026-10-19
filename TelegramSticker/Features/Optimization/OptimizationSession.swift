import SwiftUI
import UIKit

@MainActor @Observable
final class OptimizationSession: Identifiable {
    let id = UUID()
    let request: OptimizationRequest
    var running = false
    var finished = false
    var message: String?
    var progress = 0.0
    var restoreImport: ImportModel?
    var sourceLinks: [String] = []
    private var operation: Task<Void, Never>?
    private var started = false
    private var progressGeneration = UUID()
    private var jobs: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportJobs") }
    init(request: OptimizationRequest) {
        self.request = request
        if let reader = try? LibraryReader.shared(), let snapshot = try? reader.snapshot(resolvingFiles: false) {
            sourceLinks = snapshot.packs.filter { request.packIDs == nil || request.packIDs!.contains($0.id) }
                .compactMap { $0.telegramName.map { "https://t.me/addstickers/" + $0 } }
        }
    }
    func cancel() { operation?.cancel() }
    func start() {
        guard !started, !running else { return }
        guard ImportActivity.shared.count == 0 else {
            message = "다른 작업이 끝나면 다시 시도해 주세요."
            return
        }
        started = true
        running = true; progress = 0; message = nil
        let generation = UUID(); progressGeneration = generation
        ImportActivity.shared.count += 1
        operation = Task {
            await DownloadDiagnostics.shared.run(title: "용량 최적화 적용") {
                await GalleryPreviewStore.shared.cancelForForegroundWork()
                let id = await BackgroundWork.shared.begin(kind: .optimizationApply, title: "스티커 용량 최적화") { self.cancel() }
                var success = false
                defer {
                    progressGeneration = UUID()
                    running = false; ImportActivity.shared.count -= 1
                    ImportActivity.shared.libraryChangeID += 1
                    BackgroundWork.shared.end(id: id, success: success, detail: message, cancelled: Task.isCancelled,
                        notificationInfo: ["optimizationSession": self.id.uuidString])
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
                    let result = try await ImportJobCache.shared.optimize(root: jobs, writer: writer,
                        packIDs: request.packIDs, stickerIDs: request.stickerIDs, progress: report)
                    success = result.failures.isEmpty; finished = true
                    progressGeneration = UUID()
                    progress = success ? 1 : min(progress, 0.99)
                    message = "\(result.optimizedPacks)개 팩 반영 · \(ByteCountFormatter.string(fromByteCount: result.saved, countStyle: .file)) 절약" + (result.failures.isEmpty ? "" : "\n" + result.failures.joined(separator: "\n"))
                    if success { BackgroundWork.shared.report(id: id, completed: 1, total: 1, subtitle: "용량 최적화 적용 완료 · 100%", finalized: true) }
                } catch {
                    finished = true
                    message = error is CancellationError ? "중단했어요. 완료된 팩은 유지하고, 처리 중인 팩의 기존 파일은 보존해요." : error.localizedDescription
                }
            }
        }
    }
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
