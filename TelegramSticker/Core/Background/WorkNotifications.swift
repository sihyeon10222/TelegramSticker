import BackgroundTasks
import UIKit
import Foundation
import OSLog
import UserNotifications
import Observation
import SwiftUI

@MainActor @Observable
final class WorkNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkNotifications()
    struct OptimizationDestination: Equatable {
        let id = UUID()
        let sessionID: String
    }
    var pendingOptimization: OptimizationDestination?
    var pendingPackUpdates = false
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do { _ = try await center.requestAuthorization(options: [.alert]) }
        catch { DownloadDiagnostics.shared.record("완료 알림 권한 요청 실패 · " + error.localizedDescription) }
    }
    func send(title: String, body: String, identifier: String = UUID().uuidString, userInfo: [String: String] = [:]) {
        Task { await deliver(title: title, body: body, identifier: identifier, userInfo: userInfo) }
    }
    /// Await enqueueing before releasing a background execution lease.
    func deliver(title: String, body: String, identifier: String = UUID().uuidString, userInfo: [String: String] = [:]) async {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        content.title = title; content.body = body
        // Silent notifications avoid the system alert vibration on every device.
        if isViewing(content.userInfo) {
            await clearViewedNotifications()
            return
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            // A screen may have opened while notification enqueueing was suspended.
            if isViewing(content.userInfo) {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            }
        }
        catch { DownloadDiagnostics.shared.record("완료 알림 등록 실패 · " + error.localizedDescription) }
    }
    private var visibleScreens: [UUID: String] = [:]

    func setScreen(_ token: UUID, scope: String, active: Bool) {
        visibleScreens[token] = active ? scope : nil
        if active { Task { await clearViewedNotifications() } }
    }

    private func scope(for info: [AnyHashable: Any]) -> String {
        if let session = info["optimizationSession"] as? String { return "optimization:" + session }
        if info["packUpdates"] as? String == "true" { return "packUpdates" }
        // Import completion alerts from earlier app versions had no routing metadata.
        return "imports"
    }

    private func isViewing(_ info: [AnyHashable: Any]) -> Bool {
        UIApplication.shared.applicationState == .active && visibleScreens.values.contains(scope(for: info))
    }

    func clearViewedNotifications() async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered.filter { isViewing($0.request.content.userInfo) }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending.filter { isViewing($0.content.userInfo) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let info = response.notification.request.content.userInfo
        let session = info["optimizationSession"] as? String
        let isDefaultAction = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let opensPackUpdates = info["packUpdates"] as? String == "true"
        // UIKit performs snapshot/state restoration from this completion callback.
        // The async delegate bridge can invoke it on a cooperative worker thread.
        Task { @MainActor in
            if isDefaultAction, let session {
                pendingOptimization = OptimizationDestination(sessionID: session)
            }
            if isDefaultAction, opensPackUpdates { pendingPackUpdates = true }
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            if isViewing(notification.request.content.userInfo) {
                center.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
                completionHandler([])
            } else {
                completionHandler([.banner, .list])
            }
        }
    }
}

/// Track each visible window separately and stop considering background windows viewed.
private struct WorkNotificationScreen: ViewModifier {
    let scope: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var token = UUID()
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                appeared = true
                WorkNotifications.shared.setScreen(token, scope: scope, active: scenePhase == .active)
            }
            .onDisappear {
                appeared = false
                WorkNotifications.shared.setScreen(token, scope: scope, active: false)
            }
            .onChange(of: scenePhase) { _, phase in
                WorkNotifications.shared.setScreen(token, scope: scope, active: appeared && phase == .active)
            }
    }
}

extension View {
    func workNotificationScreen(_ scope: String) -> some View {
        modifier(WorkNotificationScreen(scope: scope))
    }
}
