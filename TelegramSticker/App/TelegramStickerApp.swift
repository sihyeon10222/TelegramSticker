//
//  TelegramStickerApp.swift
//  TelegramSticker
//
//  Created by 김시현 on 10/9/26.
//

import SwiftUI

@main
struct TelegramStickerApp: App {
    init() {
        _ = WorkNotifications.shared
        _ = KeyboardAccessMonitor.shared
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
        }
    }
}
