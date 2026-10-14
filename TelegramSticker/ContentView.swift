import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboarding = false
    var body: some View {
        TabView {
            Tab("내 스티커 팩", systemImage: "square.stack") { LibraryView() }
            Tab("설정", systemImage: "keyboard") { SettingsView() }
        }
        .safeAreaInset(edge: .bottom) {
            if let title = BackgroundWork.shared.title {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.caption.bold())
                        Spacer()
                        Button("중단") { BackgroundWork.shared.cancelCurrent() }.buttonStyle(.glass).font(.caption)
                    }
                    ProgressView(value: BackgroundWork.shared.fraction)
                    Text(BackgroundWork.shared.subtitle).font(.caption2).foregroundStyle(.secondary)
                }.padding(12).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $onboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                onboarding = false
            }
            .interactiveDismissDisabled()
        }
        .task { onboarding = !hasCompletedOnboarding }
    }
}

private struct SettingsView: View {
    @State private var practiceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("키보드") {
                    NavigationLink {
                        KeyboardSetupView()
                    } label: {
                        Label("키보드 추가 및 전체 접근 안내", systemImage: "keyboard")
                    }
                    .accessibilityIdentifier("keyboardSetup")
                    Label("복사한 뒤 채팅창에 직접 붙여넣으세요.", systemImage: "doc.on.clipboard")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    TextField("여기를 누른 뒤 지구본으로 전환", text: $practiceText)
                        .accessibilityIdentifier("keyboardPractice")
                } header: { Text("키보드 전환 연습") } footer: {
                    Text("이 칸에 입력한 내용은 저장하지 않아요.")
                }
                Section("저장 공간") { StorageSettingsView() }
                Section("앱 정보") {
                    NavigationLink("오픈 소스 라이선스") {
                        ScrollView {
                            Text((Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
                                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "라이선스를 열 수 없어요.")
                                .font(.footnote).textSelection(.enabled).padding()
                        }.navigationTitle("오픈 소스 라이선스")
                    }
                }
            }
            .navigationTitle("설정")
        }
    }
}

private struct KeyboardSetupView: View {
    var body: some View {
        List {
            Section("1. 키보드 추가") {
                Text("설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가에서 StickerBridge를 선택하세요.")
            }
            Section("2. 지구본으로 전환") {
                Text("입력창에서 지구본을 길게 눌러 StickerBridge를 선택하세요. Apple 한국어·영어·이모지 키보드로 돌아갈 때도 같은 방법을 사용해요.")
                Text("지구본의 위치와 전환 순서는 iOS가 정해요.")
                    .foregroundStyle(.secondary)
            }
            Section("3. 키보드에서 이미지 복사") {
                Text("설정 → 일반 → 키보드 → 키보드 → StickerBridge에서 ‘전체 접근 허용’을 켜 주세요.")
                Text("전체 접근은 키보드의 이미지 클립보드 복사를 위해 요청해요. iOS는 네트워크 등 더 넓은 권한도 부여하지만, 이 키보드는 네트워크를 사용하거나 입력 내용·기존 클립보드를 읽지 않아요.")
                Text("허용하지 않아도 설치된 스티커 보기와 키보드 전환은 가능해요. 메인 앱의 복사는 키보드의 전체 접근 설정과 관계없이 사용할 수 있어요.")
            }
            Section("붙여넣기와 전송") {
                Text("스티커를 탭해 복사한 뒤, 대상 앱 입력창에서 직접 붙여넣고 전송하세요. ‘복사됨’은 클립보드 기록 안내이며 붙여넣기·전송 성공을 뜻하지 않아요.")
                Text("비밀번호·전화번호 필드나 서드파티 키보드를 허용하지 않는 앱에서는 StickerBridge가 나타나지 않을 수 있어요. 이때는 메인 앱에서 복사해 보세요.")
            }

        }
        .navigationTitle("키보드 설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { ContentView() }
