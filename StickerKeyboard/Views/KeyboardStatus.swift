import UIKit
import os

extension KeyboardViewController {
    func refreshPermission(resetStatus: Bool = false) {
        let allowed = hasFullAccess
        if allowed { KeyboardAccessReceipt.recordAllowed() }
        guard resetStatus || previousFullAccess != allowed else { return }
        let event = allowed ? KeyboardAccessReceipt.allowedNotification : KeyboardAccessReceipt.deniedNotification
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: event as CFString), nil, nil, true)
        previousFullAccess = allowed
        resetStatusTask?.cancel()
        state.clearCopiedSticker()
        collectionView.visibleCells.compactMap { $0 as? StickerCell }.forEach { $0.setCopied(false) }
        showIdleStatus()
    }

    func showIdleStatus() {
        toast.isHidden = true
        statusLabel.text = nil
    }

    func showMessage(_ message: String, copied: Bool = false, persistent: Bool = false) {
        resetStatusTask?.cancel()
        statusLabel.text = message
        statusLabel.textColor = copied ? .label : .secondaryLabel
        toast.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
        guard !persistent else { return }
        resetStatusTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.state.clearCopiedSticker()
            self?.collectionView.visibleCells.compactMap { $0 as? StickerCell }.forEach { $0.setCopied(false) }
            self?.showIdleStatus()
        }
    }
}
