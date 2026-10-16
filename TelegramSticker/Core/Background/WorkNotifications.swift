import BackgroundTasks
import UIKit
import Foundation
import OSLog
import UserNotifications
import Observation

@MainActor @Observable
final class WorkNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkNotifications()
    struct OptimizationDestination: Equatable {
        let id = UUID()
        let sessionID: String
        let profile: String
    }
    var pendingOptimization: OptimizationDestination?
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { DownloadDiagnostics.shared.record("완료 알림 권한 요청 실패 · " + error.localizedDescription) }
    }
    func send(title: String, body: String, identifier: String = UUID().uuidString, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        content.title = title; content.body = body; content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task {
            do { try await UNUserNotificationCenter.current().add(request) }
            catch { DownloadDiagnostics.shared.record("완료 알림 등록 실패 · " + error.localizedDescription) }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let info = response.notification.request.content.userInfo
        let session = info["optimizationSession"] as? String
        let profile = info["optimizationProfile"] as? String
        let isDefaultAction = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        // UIKit performs snapshot/state restoration from this completion callback.
        // The async delegate bridge can invoke it on a cooperative worker thread.
        Task { @MainActor in
            if isDefaultAction, let session, let profile {
                pendingOptimization = OptimizationDestination(sessionID: session, profile: profile)
            }
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler([.banner, .list, .sound]) }
    }
}
