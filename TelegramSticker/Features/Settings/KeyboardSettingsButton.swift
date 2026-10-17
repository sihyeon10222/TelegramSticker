import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct KeyboardSettingsButton: View {
    var destination: KeyboardSetupAction.Kind = .fullAccess
    @State private var failedToOpen = false
    var body: some View {
        Button {
            Task { @MainActor in
                switch destination {
                case .add:
                    // Open Settings without requesting any nested preference pane.
                    guard let url = URL(string: "App-prefs:") else { failedToOpen = true; return }
                    failedToOpen = !(await UIApplication.shared.open(url))
                case .fullAccess:
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { failedToOpen = true; return }
                    failedToOpen = !(await UIApplication.shared.open(url))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gear")
                Text("설정 열기")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .appGlassButton()
            .alert("설정에서 직접 이동해 주세요", isPresented: $failedToOpen) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(destination == .add
                    ? "설정 앱을 직접 열고 일반 → 키보드 → 키보드 → 새로운 키보드 추가에서 StickerBridge를 선택하세요."
                    : "설정 → 앱 → StickerBridge → 키보드에서 전체 접근 허용을 켜 주세요.")
            }
    }
}
