import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Observations from the running extension, never a live Settings query.
@MainActor @Observable
final class KeyboardAccessMonitor {
    static let shared = KeyboardAccessMonitor()
    enum Status { case unknown, allowed, denied }
    var status: Status = .unknown
    private init() {
        refresh()
        let callback: CFNotificationCallback = { _, _, name, _, _ in
            guard let name else { return }
            let denied = name.rawValue as String == KeyboardAccessReceipt.deniedNotification
            Task { @MainActor in
                if denied { KeyboardAccessReceipt.recordDeniedFromApp() }
                else { KeyboardAccessReceipt.recordAllowed() }
                KeyboardAccessMonitor.shared.refresh()
            }
        }
        for event in [KeyboardAccessReceipt.allowedNotification, KeyboardAccessReceipt.deniedNotification] {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil,
                callback, event as CFString, nil, .deliverImmediately)
        }
    }
    func refresh() {
        if KeyboardAccessReceipt.lastAllowed != nil { status = .allowed }
        else if KeyboardAccessReceipt.lastDenied != nil { status = .denied }
        else { status = .unknown }
    }
}
