import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Reminder does not block unrelated app functions or misrepresent unknown state as denied.
struct KeyboardPermissionReminder: ViewModifier {
    let working: Bool
    @State private var showing = false
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
        #else
        content
            .onChange(of: working) { _, active in
                if active, KeyboardAccessReceipt.lastAllowed == nil { showing = true }
            }
            .alert("키보드 전체 접근을 확인해 주세요", isPresented: $showing) {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("계속 진행", role: .cancel) {}
            } message: {
                Text("작업은 계속 진행돼요. 키보드에서 스티커를 복사하려면 설정 → StickerBridge → 키보드 → 전체 접근 허용을 켜고 키보드를 한 번 열어 주세요.")
            }
        #endif
    }
}
