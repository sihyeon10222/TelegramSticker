import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                #if !targetEnvironment(macCatalyst)
                Section("키보드") {
                    KeyboardSetupAction(kind: .add)
                    KeyboardSetupAction(kind: .fullAccess)
                }
                #endif
                #if targetEnvironment(macCatalyst)
                MacDesktopSettings()
                #endif
                SyncSettingsView()
                Section("저장 공간") { StorageSettingsView() }
                Section("앱 초기화") { AppResetButton() }
                Section("진단") { NavigationLink("다운로드 로그") { DownloadLogsView() } }
                Section("앱 정보") {
                    LabeledContent("앱 버전", value: appVersion)
                        .accessibilityIdentifier("settingsAppVersion")
                    LabeledContent("빌드 번호", value: appBuild)
                        .accessibilityIdentifier("settingsAppBuild")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { CurrentWorkBanner() }
            .contentMargins(.bottom, 12, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("설정")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
