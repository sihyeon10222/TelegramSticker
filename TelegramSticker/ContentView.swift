import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboarding = false
    @Bindable private var imports = ImportActivity.shared
    @Bindable private var optimizations = OptimizationCenter.shared
    @Bindable private var linkInbox = PackLinkInbox.shared
    var body: some View {
        TabView {
            Tab("내 스티커 팩", systemImage: "square.stack") { LibraryView() }
            Tab("갤러리", systemImage: "square.grid.2x2") { GalleryView() }
            Tab("설정", systemImage: "keyboard") {
                SettingsView()
            }
        }
        .sheet(item: $imports.presentedImport) { session in
            ImportView(model: session)
        }
        .sheet(item: $optimizations.presented) { OptimizationView(model: $0) }
        .alert("스티커 용량을 줄여볼까요?", isPresented: Binding(
            get: { imports.optimizationSuggestion != nil && imports.visibleImportIDs.isEmpty },
            set: { if !$0 { imports.optimizationSuggestion = nil } }
        )) {
            Button("용량 최적화") {
                if let request = imports.optimizationSuggestion { optimizations.presented = optimizations.session(for: request) }
                imports.optimizationSuggestion = nil
            }
            Button("나중에", role: .cancel) { imports.optimizationSuggestion = nil }
        } message: { Text("설치한 팩의 화질을 비교하고 저장 공간을 줄일 수 있어요.") }
        .sheet(item: $linkInbox.received) { ReceivedPackLinksView(received: $0) }
        .onOpenURL { url in Task { await linkInbox.open(url) } }
        .alert("링크 목록 파일 가져오기", isPresented: Binding(get: { linkInbox.error != nil }, set: { if !$0 { linkInbox.error = nil } })) {
            Button("확인", role: .cancel) { linkInbox.error = nil }
        } message: { Text(linkInbox.error ?? "") }
        .sheet(isPresented: $onboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                onboarding = false
            }
            .interactiveDismissDisabled()
        }
        .task { onboarding = !hasCompletedOnboarding }
        .onChange(of: hasCompletedOnboarding) { _, complete in if !complete { onboarding = true } }
    }
}

/// Lives above the tab bar, alongside the library's selection actions.
struct CurrentWorkBanner: View {
    var body: some View {
        if let title = BackgroundWork.shared.title {
            HStack(spacing: 12) {
                Button {
                    if ImportActivity.shared.current?.busy == true { ImportActivity.shared.presentCurrent() }
                    else { OptimizationCenter.shared.presentCurrent() }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(title).font(.caption.bold())
                            Spacer()
                        }
                        ProgressView(value: BackgroundWork.shared.fraction)
                            .tint(ImportActivity.shared.current?.busy == true ? ImportActivity.shared.current?.progressColor ?? .blue : .blue)
                        Text(BackgroundWork.shared.subtitle)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(ImportActivity.shared.current?.busy == true && (ImportActivity.shared.current?.failedCount ?? 0) > 0 ? Color.red : Color.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(ImportActivity.shared.current?.busy != true && OptimizationCenter.shared.current?.running != true)
                .accessibilityLabel("진행 중인 작업 열기")
                .accessibilityIdentifier("backgroundWorkDetails")
                Button("중단") { BackgroundWork.shared.cancelCurrent() }
                    .buttonStyle(.glass).font(.caption)
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }
}

private struct SettingsView: View {
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

#Preview { ContentView() }
