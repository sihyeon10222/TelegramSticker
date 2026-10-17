//
//  TelegramStickerApp.swift
//  TelegramSticker
//
//  Created by 김시현 on 10/9/26.
//

import SwiftUI

@main
struct TelegramStickerApp: App {
    @UIApplicationDelegateAdaptor(StickerAppDelegate.self) private var appDelegate
    init() {
        _ = WorkNotifications.shared
        #if !targetEnvironment(macCatalyst)
        _ = KeyboardAccessMonitor.shared
        #endif
        _ = GalleryPreviewState.shared
        Task { await GalleryPreviewState.shared.restoreRemaining() }
        // Capture only files left by the previous process, before any new comparison starts.
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let stale = ((try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("StickerOptimization-") && UUID(uuidString: String($0.lastPathComponent.dropFirst("StickerOptimization-".count))) != nil }
        Task.detached(priority: .utility) {
            for directory in stale {
                guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if targetEnvironment(macCatalyst)
                // Scene restrictions include the title bar; content must fit the remaining space.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { MacWindowConfiguration() }
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.automatic)
        .commands { StickerMacCommands() }
        #endif
    }
}
