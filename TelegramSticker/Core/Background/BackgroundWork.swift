import BackgroundTasks
import UIKit
import Foundation
import OSLog
import UserNotifications

/// CPU/network-only continued processing. The OS owns the progress Live Activity.
@MainActor @Observable
final class BackgroundWork {
    static let shared = BackgroundWork()
    private let logger = Logger(subsystem: "com.sihyeon.TelegramSticker", category: "BackgroundWork")
    var notice: String?
    enum Kind: Sendable {
        case download, update, restoreOriginal, optimizationPreparation, optimizationApply
        var sendsCompletion: Bool {
            switch self {
            case .download, .update, .restoreOriginal, .optimizationPreparation, .optimizationApply: true
            }
        }
    }
    private struct Job {
        let kind: Kind
        let title: String
        let cancel: @MainActor () -> Void
        var task: BGContinuedProcessingTask?
        var bridge: UIBackgroundTaskIdentifier = .invalid
        var completed: Int64 = 0
        var total: Int64 = 1
        var subtitle = "준비 중"
        var finalized = false
        var lastPublished = Date.distantPast
        var publishedSubtitle: String?
    }
    private var jobs: [String: Job] = [:]
    var title: String? { jobs.values.first?.title }
    var subtitle: String { jobs.values.first?.subtitle ?? "" }
    var fraction: Double { guard let job = jobs.values.first else { return 0 }; let fraction = Double(job.completed) / Double(max(1, job.total)); return job.finalized ? fraction : min(0.99, fraction) }
    func cancelCurrent() { jobs.values.first?.cancel() }

    func begin(kind: Kind, title: String, cancel: @escaping @MainActor () -> Void) async -> String? {
        let identifier = "com.sihyeon.TelegramSticker.work." + UUID().uuidString
        // Foreground progress and navigation must also work when the OS cannot
        // grant continued processing (including Simulator).
        jobs[identifier] = Job(kind: kind, title: title, cancel: cancel)
        let bridge = UIApplication.shared.beginBackgroundTask(withName: title) {
            Task { @MainActor in
                guard var job = BackgroundWork.shared.jobs[identifier] else { return }
                if job.bridge != .invalid { UIApplication.shared.endBackgroundTask(job.bridge); job.bridge = .invalid }
                BackgroundWork.shared.jobs[identifier] = job
                if job.task == nil { BackgroundWork.shared.notice = "iOS 작업 승인을 기다리고 있어요. 승인되거나 앱으로 돌아오면 자동으로 계속해요." }
            }
        }
        jobs[identifier]?.bridge = bridge
        Task { await WorkNotifications.shared.requestAuthorizationIfNeeded() }
        #if targetEnvironment(simulator)
        notice = "Simulator에서는 백그라운드 진행 표시를 검증할 수 없어요."
        return identifier
        #else
        guard BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main, launchHandler: { task in
            guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in BackgroundWork.shared.attach(task, id: identifier) }
        }) else {
            notice = "백그라운드 작업을 등록하지 못했어요. 앱을 열어 두면 계속 진행해요."
            return identifier
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "준비 중")
        request.strategy = .queue
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
            notice = nil
            logger.info("Continued processing request accepted")
            return identifier
        } catch {
            notice = "현재 iOS가 백그라운드 실행을 허용하지 않아요. 앱을 열어 두면 계속 진행해요. (\((error as NSError).code))"
            return identifier
        }
        #endif
    }
    private func attach(_ task: BGContinuedProcessingTask, id: String) {
        guard var job = jobs[id] else { task.setTaskCompleted(success: false); return }
        task.expirationHandler = {
            Task { @MainActor in
                guard let job = BackgroundWork.shared.jobs[id] else { return }
                job.cancel()
                BackgroundWork.shared.notice = "iOS 또는 사용자가 작업을 중단했어요. 앱에서 다시 시도하면 설치 완료된 팩은 건너뛰어요."
            }
        }
        logger.info("Continued processing execution granted")
        if job.bridge != .invalid { UIApplication.shared.endBackgroundTask(job.bridge); job.bridge = .invalid }
        job.task = task; jobs[id] = job
        notice = nil
        report(id: id, completed: job.completed, total: job.total, subtitle: job.subtitle, finalized: job.finalized, force: true)
    }
    /// No work should be counted as failed merely because iOS has suspended the app
    /// before granting continued processing. Cancellation/expiration still terminates it.
    func waitForExecution() async throws {
        #if !targetEnvironment(simulator)
        while UIApplication.shared.applicationState == .background &&
            !jobs.values.contains(where: { $0.task != nil || $0.bridge != .invalid }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(250))
        }
        #endif
        try Task.checkCancellation()
    }

    func report(id: String?, completed: Int64, total: Int64, subtitle: String, finalized: Bool = false, force: Bool = false) {
        guard let id, var job = jobs[id] else { return }
        job.total = max(1, total)
        job.completed = min(job.total, max(job.completed, completed))
        job.subtitle = subtitle
        job.finalized = job.finalized || finalized
        jobs[id] = job
        guard let task = job.task, force || finalized || Date().timeIntervalSince(job.lastPublished) >= 1 else { return }
        let changed = job.publishedSubtitle != subtitle
        job.lastPublished = Date(); job.publishedSubtitle = subtitle; jobs[id] = job
        task.progress.totalUnitCount = job.total * 100
        task.progress.completedUnitCount = job.finalized ? job.completed * 100 : min(job.completed * 100, job.total * 99)
        if force || changed { task.updateTitle(job.title, subtitle: subtitle) }
    }
    func end(id: String?, success: Bool, detail: String? = nil, cancelled: Bool = false) {
        DownloadDiagnostics.shared.finish(success: success, summary: detail, cancelled: cancelled)
        guard let id, let job = jobs.removeValue(forKey: id) else { return }
        if job.bridge != .invalid { UIApplication.shared.endBackgroundTask(job.bridge) }
        if success { job.task?.progress.completedUnitCount = job.task?.progress.totalUnitCount ?? 1 }
        logger.info("Continued processing completed, success: \(success)")
        job.task?.setTaskCompleted(success: success)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
        if job.kind.sendsCompletion, !cancelled {
            WorkNotifications.shared.send(title: job.title + (success ? " 완료" : " 종료 · 확인 필요"),
                                          body: detail ?? job.subtitle, identifier: id)
        }
    }
}
