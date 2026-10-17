import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var verified = KeyboardAccessReceipt.lastAllowed != nil
    @State private var verificationText = ""
    @FocusState private var verificationFocused: Bool

    var body: some View {
        #if targetEnvironment(macCatalyst)
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "square.stack").font(.system(size: 44)).foregroundStyle(.tint)
                Text("맥에서 스티커를 사용하세요").font(.largeTitle.bold())
                Label("팩 링크나 갤러리에서 스티커 팩 설치", systemImage: "1.circle")
                Label("스티커를 선택한 뒤 복사 또는 ⌘C", systemImage: "2.circle")
                Label("채팅창에서 ⌘V로 붙여넣기", systemImage: "3.circle")
                Text(LibraryChangeJournal.cloudKitConfigured ? "같은 Apple 계정의 iCloud로 팩 목록과 순서를 동기화합니다. 스티커 파일은 각 기기에서 다운로드해요." : "팩은 이 맥에 저장됩니다. iCloud 동기화는 지원하는 Apple Developer 팀으로 앱을 서명한 뒤 사용할 수 있어요.").foregroundStyle(.secondary)
                Button("시작하기", action: finish).appGlassButton(prominent: true).controlSize(.large)
            }.padding(32).frame(maxWidth: 640)
            .navigationTitle("StickerBridge 시작")
        }
        #else
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
                    }.appGlassButton(prominent: true)
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
        #endif
    }
    private func refreshVerification() {
        // A previously confirmed permission must not be discarded just because
        // this SwiftUI sheet was recreated after returning from Settings.
        verified = KeyboardAccessReceipt.lastAllowed != nil
        if verified { verificationFocused = false }
    }

}
