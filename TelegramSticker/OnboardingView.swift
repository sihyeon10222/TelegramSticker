import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "square.stack").font(.system(size: 44)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("스티커가 필요할 때,\n키보드를 바꿔 보세요.").font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("한국어·영어·숫자·이모지는 평소 Apple 키보드로 입력하세요. StickerBridge는 다운로드한 스티커를 고르는 키보드예요.")
                    step("1. 팩 추가", symbol: "plus.circle", text: "내 스티커 팩의 +에서 공개 Telegram 링크를 추가하세요. 설치한 PNG·GIF는 인터넷 없이 쓸 수 있어요.")
                    step("2. 키보드 추가", symbol: "keyboard", text: "설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → StickerBridge를 선택하세요.")
                    step("3. 지구본으로 선택", symbol: "globe", text: "채팅창에서 지구본을 길게 눌러 StickerBridge를 선택하세요. 기본 키보드로 돌아갈 때도 같은 방법을 써요. 전환 순서는 iOS가 정해요.")
                    step("4. 복사 후 붙여넣기", symbol: "doc.on.doc", text: "스티커를 탭하고 채팅창에 직접 붙여넣어 전송하세요. 이미지 붙여넣기·투명도는 대상 앱에 따라 달라요.")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("전체 접근은 이미지 복사에 필요해요").font(.headline)
                        Text("설정의 StickerBridge 키보드에서 ‘전체 접근 허용’을 켜 주세요. 허용하지 않아도 스티커 보기와 키보드 전환은 가능해요.")
                        Text("키보드는 네트워크를 사용하거나 입력 내용·기존 클립보드를 읽지 않아요. 최근 복사한 스티커 ID만 최대 24개 기기에 저장해요.")
                            .foregroundStyle(.secondary)
                    }
                    Text("비밀번호 입력창 등에서는 이 키보드가 나타나지 않을 수 있어요. 메인 앱의 복사·공유도 이용할 수 있어요. 설정 탭에서 이 안내를 다시 확인할 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("시작하기", action: finish).buttonStyle(.glassProminent)
                        .controlSize(.large).accessibilityIdentifier("finishOnboarding")
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle("StickerBridge 시작")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("나중에", action: finish).accessibilityIdentifier("skipOnboarding")
            } }
        }
    }
    private func step(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader)
            Text(text)
        }
    }
}
