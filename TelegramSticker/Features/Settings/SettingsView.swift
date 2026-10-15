import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("키보드") {
                    KeyboardSetupAction(kind: .add)
                    KeyboardSetupAction(kind: .fullAccess)
                }
                Section("저장 공간") { StorageSettingsView() }
                Section("앱 초기화") { AppResetButton() }
                Section("진단") { NavigationLink("다운로드 로그") { DownloadLogsView() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { CurrentWorkBanner() }
            .contentMargins(.bottom, 12, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("설정")
        }
    }
}
