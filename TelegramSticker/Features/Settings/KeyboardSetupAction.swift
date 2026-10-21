import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct KeyboardSetupAction: View {
    enum Kind { case add, fullAccess }
    let kind: Kind
    @Bindable private var access = KeyboardAccessMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label(kind == .add ? "키보드 추가" : "키보드 전체 접근을 허용해 주세요",
                      systemImage: kind == .add ? "keyboard.badge.ellipsis" : "keyboard")
                    .font(.headline)
                Spacer(minLength: 8)
                if kind == .fullAccess {
                    Image(systemName: access.status == .allowed ? "checkmark.circle.fill" : access.status == .denied ? "xmark.circle.fill" : "questionmark.circle")
                        .foregroundStyle(access.status == .allowed ? Color.green : access.status == .denied ? Color.red : Color.secondary)
                        .accessibilityLabel(access.status == .allowed ? "마지막 확인: 허용" : access.status == .denied ? "마지막 확인: 미허용" : "허용 상태 미확인")
                }
            }
            if kind == .fullAccess {
                Text(access.status == .allowed ? "마지막 확인: 허용" : access.status == .denied ? "마지막 확인: 미허용" : "아직 확인되지 않았어요. StickerBridge 키보드를 한 번 열어 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
                if access.status != .unknown {
                    Text("설정에서 변경한 상태는 키보드를 다시 열면 확인할 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(kind == .add
                ? "설정 → 일반 → 키보드 → 키보드에서 새로운 키보드 추가 → StickerBridge를 선택하세요."
                : "열리는 StickerBridge 설정에서 키보드 → 전체 접근 허용을 켜 주세요. 키보드는 입력 내용을 수집하지 않아요.")
                .font(.footnote).foregroundStyle(.secondary)
            KeyboardSettingsButton(destination: kind)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { access.refresh() } }
        .task {
            guard kind == .fullAccess else { return }
            while !Task.isCancelled {
                access.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
