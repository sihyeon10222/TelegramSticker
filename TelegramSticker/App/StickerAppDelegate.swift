import UIKit

final class StickerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if targetEnvironment(macCatalyst)
        MacDesktopCoordinator.shared.start()
        #endif
        if LibraryChangeJournal.cloudKitConfigured { application.registerForRemoteNotifications() }
        return true
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            await LibrarySyncService.shared.synchronize()
            SyncDownloadCoordinator.shared.reconcile()
            completionHandler(.newData)
        }
    }
}
