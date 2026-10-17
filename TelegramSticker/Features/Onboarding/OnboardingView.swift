import SwiftUI
import UIKit

struct OnboardingView: View {
    let finish: () -> Void

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("마음에 드는 텔레그램 스티커를 다른 채팅에서도.")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        step("1", title: "스티커 팩 추가", detail: "갤러리에서 고르거나, 텔레그램 팩 링크를 가져오세요.")
                        #if targetEnvironment(macCatalyst)
                        step("2", title: "어디서든 열고 복사", detail: "메뉴 막대 아이콘이나 \(shortcut)로 열고 스티커를 클릭하세요.")
                        step("3", title: "채팅에 붙여넣기", detail: "보낼 채팅창에서 ⌘V를 누르세요.")
                        #else
                        step("2", title: "탭해서 복사", detail: isPad
                             ? "앱에서 스티커를 탭하세요. 채팅 앱을 나란히 열어두면 더 편해요."
                             : "앱에서 원하는 스티커를 탭하세요.")
                        step("3", title: "채팅에 붙여넣기", detail: "채팅 입력칸을 길게 누르고 ‘붙여넣기’를 선택하세요.")
                        #endif
                    }
                    #if targetEnvironment(macCatalyst)
                    Text("로그인 시 실행과 메뉴 막대 표시가 기본으로 켜져 있어요. 설정에서 바꿀 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    #else
                    VStack(alignment: .leading, spacing: 16) {
                        Text("채팅 중에는 스티커 키보드로")
                            .font(.headline)
                            .foregroundStyle(.tint)
                            .accessibilityAddTraits(.isHeader)
                        Text("키보드를 추가하고 전체 접근을 허용한 뒤, 채팅에서 지구본을 길게 눌러 StickerBridge를 선택하세요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        KeyboardSetupAction(kind: .add)
                        KeyboardSetupAction(kind: .fullAccess)
                    }
                    #endif
                    Text("이미지 붙여넣기를 지원하는 앱에서 사용할 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(28)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button("시작하기", action: finish)
                    .appGlassButton(prominent: true)
                    .controlSize(.large)
                    .accessibilityIdentifier("finishOnboarding")
                    .padding(20)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("StickerBridge")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }

    private var title: String {
        #if targetEnvironment(macCatalyst)
        "맥에서 바로 꺼내 쓰세요"
        #else
        isPad ? "아이패드에서 더 편하게 보내세요" : "좋아하는 스티커를 보내세요"
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var shortcut: String {
        MacDesktopCoordinator.shared.settings["shortcut"] as? String ?? "⌥⇧S"
    }
    #endif

    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.subheadline.bold()).foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(.tint.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
