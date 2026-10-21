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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .toggleStyle(AppQuietToggleStyle())
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
