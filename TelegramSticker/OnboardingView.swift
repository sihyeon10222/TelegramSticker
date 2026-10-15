import SwiftUI
import UIKit

struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var verified = KeyboardAccessReceipt.lastAllowed != nil
    @State private var verificationText = ""
    @FocusState private var verificationFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "keyboard").font(.system(size: 44)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("키보드를 먼저 설정해 주세요").font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("StickerBridge 키보드에서 스티커를 복사할 수 있도록 전체 접근을 허용해 주세요.")
                        .foregroundStyle(.secondary)
                    KeyboardSetupAction(kind: .add)
                    KeyboardSetupAction(kind: .fullAccess)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(verified ? "전체 접근 허용을 확인했어요" : "허용 상태 확인", systemImage: verified ? "checkmark.circle.fill" : "keyboard")
                            .font(.headline).foregroundStyle(verified ? Color.green : Color.primary)
                        if !verified {
                            Text("설정을 마친 뒤 아래 입력칸을 누르고, 지구본을 길게 눌러 StickerBridge를 선택하세요. 키보드가 전체 접근을 확인하면 시작하기가 켜져요.")
                                .font(.footnote).foregroundStyle(.secondary)
                            TextField("여기를 눌러 StickerBridge 키보드 선택", text: $verificationText)
                                .textFieldStyle(.roundedBorder)
                                .focused($verificationFocused)
                                .submitLabel(.done)
                                .onSubmit { verificationFocused = false }
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                                .accessibilityIdentifier("verifyKeyboardAccess")
                            Button("허용 상태 다시 확인") { refreshVerification() }
                                .font(.footnote)
                        }
                    }
                    Button("시작하기") {
                        guard verified else { return }
                        verificationFocused = false
                        finish()
                    }.buttonStyle(.glassProminent)
                        .controlSize(.large).disabled(!verified)
                        .accessibilityIdentifier("finishOnboarding")
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshVerification() } }
            .navigationTitle("StickerBridge 시작")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .task {
                while !Task.isCancelled {
                    refreshVerification()
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                }
            }
        }
    }
    private func refreshVerification() {
        // A previously confirmed permission must not be discarded just because
        // this SwiftUI sheet was recreated after returning from Settings.
        verified = KeyboardAccessReceipt.lastAllowed != nil
        if verified { verificationFocused = false }
    }

}

struct KeyboardSettingsButton: View {
    var destination: KeyboardSetupAction.Kind = .fullAccess
    @State private var failedToOpen = false
    var body: some View {
        Button("아이폰 설정 열기", systemImage: "gear") {
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
        }.buttonStyle(.glass)
            .alert("설정에서 직접 이동해 주세요", isPresented: $failedToOpen) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(destination == .add
                    ? "설정 앱을 직접 열고 일반 → 키보드 → 키보드 → 새로운 키보드 추가에서 StickerBridge를 선택하세요."
                    : "설정 → 앱 → StickerBridge → 키보드에서 전체 접근 허용을 켜 주세요.")
            }
    }
}

/// Observations from the running extension, never a live Settings query.
@MainActor @Observable
final class KeyboardAccessMonitor {
    static let shared = KeyboardAccessMonitor()
    enum Status { case unknown, allowed, denied }
    var status: Status = .unknown
    private init() {
        refresh()
        let callback: CFNotificationCallback = { _, _, name, _, _ in
            guard let name else { return }
            let denied = name.rawValue as String == KeyboardAccessReceipt.deniedNotification
            Task { @MainActor in
                if denied { KeyboardAccessReceipt.recordDeniedFromApp() }
                else { KeyboardAccessReceipt.recordAllowed() }
                KeyboardAccessMonitor.shared.refresh()
            }
        }
        for event in [KeyboardAccessReceipt.allowedNotification, KeyboardAccessReceipt.deniedNotification] {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil,
                callback, event as CFString, nil, .deliverImmediately)
        }
    }
    func refresh() {
        if KeyboardAccessReceipt.lastAllowed != nil { status = .allowed }
        else if KeyboardAccessReceipt.lastDenied != nil { status = .denied }
        else { status = .unknown }
    }
}

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

struct KeyboardPermissionNotice: View {
    var body: some View { KeyboardSetupAction(kind: .fullAccess) }
}

/// Reminder does not block unrelated app functions or misrepresent unknown state as denied.
struct KeyboardPermissionReminder: ViewModifier {
    let working: Bool
    @State private var showing = false
    func body(content: Content) -> some View {
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
    }
}
