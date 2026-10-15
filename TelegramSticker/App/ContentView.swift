import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum AppTab: Hashable { case library, gallery, settings }

private struct AppTabKey: EnvironmentKey {
    static let defaultValue = AppTab.library
}

extension EnvironmentValues {
    var activeAppTab: AppTab {
        get { self[AppTabKey.self] }
        set { self[AppTabKey.self] = newValue }
    }
}

struct ContentView: View {
    @State private var selectedTab = AppTab.library
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboarding = false
    @Bindable private var imports = ImportActivity.shared
    @Bindable private var optimizations = OptimizationCenter.shared
    @Bindable private var linkInbox = PackLinkInbox.shared
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("내 스티커 팩", systemImage: "square.stack", value: AppTab.library) { LibraryView() }
            Tab("갤러리", systemImage: "square.grid.2x2", value: AppTab.gallery) { GalleryView() }
            Tab("설정", systemImage: "keyboard", value: AppTab.settings) {
                SettingsView()
            }
        }
        .environment(\.activeAppTab, selectedTab)
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

#Preview { ContentView() }
