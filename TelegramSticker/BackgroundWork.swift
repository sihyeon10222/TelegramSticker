import BackgroundTasks
import Foundation
import OSLog

/// CPU/network-only continued processing. The OS owns the progress Live Activity.
@MainActor @Observable
final class BackgroundWork {
    static let shared = BackgroundWork()
    private let logger = Logger(subsystem: "com.sihyeon.TelegramSticker", category: "BackgroundWork")
    var notice: String?
    private struct Job {
        let title: String
        let cancel: @MainActor () -> Void
        var task: BGContinuedProcessingTask?
        var completed: Int64 = 0
        var total: Int64 = 1
        var subtitle = "준비 중"
    }
    private var jobs: [String: Job] = [:]
    var title: String? { jobs.values.first?.title }
    var subtitle: String { jobs.values.first?.subtitle ?? "" }
    var fraction: Double { guard let job = jobs.values.first else { return 0 }; return Double(job.completed) / Double(max(1, job.total)) }
    func cancelCurrent() { jobs.values.first?.cancel() }

    func begin(title: String, cancel: @escaping @MainActor () -> Void) async -> String? {
        #if targetEnvironment(simulator)
        notice = "Simulator에서는 백그라운드 진행 표시를 검증할 수 없어요."
        return nil
        #else
        let identifier = "com.sihyeon.TelegramSticker.work." + UUID().uuidString
        jobs[identifier] = Job(title: title, cancel: cancel)
        guard BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main, launchHandler: { task in
            guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in BackgroundWork.shared.attach(task, id: identifier) }
        }) else {
            jobs.removeValue(forKey: identifier)
            notice = "백그라운드 작업을 등록하지 못했어요. 앱을 열어 두면 계속 진행해요."
            return nil
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "준비 중")
        request.strategy = .fail
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
            notice = nil
            logger.info("Continued processing request accepted")
            return identifier
        } catch {
            jobs.removeValue(forKey: identifier)
            notice = "현재 iOS가 백그라운드 실행을 허용하지 않아요. 앱을 열어 두면 계속 진행해요. (\((error as NSError).code))"
            return nil
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
        job.task = task; jobs[id] = job
        report(id: id, completed: job.completed, total: job.total, subtitle: job.subtitle)
    }
    func report(id: String?, completed: Int64, total: Int64, subtitle: String) {
        guard let id, var job = jobs[id] else { return }
        job.total = max(1, total)
        job.completed = min(job.total, max(job.completed, completed))
        job.subtitle = subtitle
        jobs[id] = job
        job.task?.progress.totalUnitCount = job.total
        job.task?.progress.completedUnitCount = job.completed
        job.task?.updateTitle(job.title, subtitle: subtitle)
    }
    func end(id: String?, success: Bool) {
        guard let id, let job = jobs.removeValue(forKey: id) else { return }
        if success { job.task?.progress.completedUnitCount = job.task?.progress.totalUnitCount ?? 1 }
        logger.info("Continued processing completed, success: \(success)")
        job.task?.setTaskCompleted(success: success)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
    }
}
