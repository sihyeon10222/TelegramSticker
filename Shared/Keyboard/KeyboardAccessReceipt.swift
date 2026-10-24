import Foundation

/// A historical observation, not a live permission query from the containing app.
nonisolated enum KeyboardAccessReceipt {
    private static let observationQueue = DispatchQueue(
        label: "com.sihyeon.TelegramSticker.keyboardAccess", qos: .utility)
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LibraryReader.appGroup)?
            .appendingPathComponent("keyboard-access-observed.json")
    }
    static let allowedNotification = "com.sihyeon.TelegramSticker.keyboardAccess.allowed"
    static let deniedNotification = "com.sihyeon.TelegramSticker.keyboardAccess.denied"
    private static let observationKey = "keyboardFullAccessObservedAt"
    private static let deniedKey = "keyboardFullAccessDeniedAt"

    /// Receipt/defaults synchronization must not delay the keyboard's first frame.
    /// Serialize observations so rapid permission changes keep notification order.
    static func publishObservation(allowed: Bool) {
        observationQueue.async {
            if allowed { recordAllowed() }
            let event = allowed ? allowedNotification : deniedNotification
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(rawValue: event as CFString), nil, nil, true)
        }
    }

    static var lastDenied: Date? {
        let defaults = UserDefaults(suiteName: LibraryReader.appGroup)
        defaults?.synchronize()
        return defaults?.object(forKey: deniedKey) as? Date
    }
    /// Called by the containing app after receiving the extension's observation.
    /// A keyboard without Full Access cannot persist shared-container changes itself.
    static func recordDeniedFromApp() {
        if let url { try? FileManager.default.removeItem(at: url) }
        let defaults = UserDefaults(suiteName: LibraryReader.appGroup)
        defaults?.removeObject(forKey: observationKey)
        defaults?.set(Date(), forKey: deniedKey)
        defaults?.synchronize()
    }
    static func recordAllowed() {
        let now = Date()
        if let observed = lastAllowed, now.timeIntervalSince(observed) < 2 { return }
        if let url, let data = try? JSONEncoder().encode(now) { try? data.write(to: url, options: .atomic) }
        // Independent fallback if receipt-file publication temporarily fails.
        if let defaults = UserDefaults(suiteName: LibraryReader.appGroup) {
            defaults.removeObject(forKey: deniedKey)
            defaults.set(now, forKey: observationKey)
            defaults.synchronize()
        }
    }
    static var lastAllowed: Date? {
        let defaults = UserDefaults(suiteName: LibraryReader.appGroup)
        defaults?.synchronize()
        let fileDate: Date? = url.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
        guard let observed = fileDate ?? (defaults?.object(forKey: observationKey) as? Date) else { return nil }
        if let denied = defaults?.object(forKey: deniedKey) as? Date, denied >= observed { return nil }
        return observed
    }
}
