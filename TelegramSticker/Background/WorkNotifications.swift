import BackgroundTasks
import UIKit
import Foundation
import OSLog
import UserNotifications

@MainActor
final class WorkNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkNotifications()
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
    func send(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task {
            do { try await UNUserNotificationCenter.current().add(request) }
            catch { DownloadDiagnostics.shared.record("완료 알림 등록 실패 · " + error.localizedDescription) }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
