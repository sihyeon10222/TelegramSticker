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

private struct LibraryHomeRequestKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    var libraryHomeRequest: Int {
        get { self[LibraryHomeRequestKey.self] }
        set { self[LibraryHomeRequestKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab = AppTab.library
    @State private var libraryHomeRequest = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboarding = false
    @Bindable private var imports = ImportActivity.shared
    @Bindable private var optimizations = OptimizationCenter.shared
    @Bindable private var notifications = WorkNotifications.shared
    @State private var optimizationNotificationError = false
    @Bindable private var linkInbox = PackLinkInbox.shared
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("내 스티커 팩", systemImage: "square.stack", value: AppTab.library) {
                LibraryView().environment(\.horizontalSizeClass, horizontalSizeClass)
                    .background { TabReselectionObserver { libraryHomeRequest += 1 } }
            }
            Tab("갤러리", systemImage: "square.grid.2x2", value: AppTab.gallery) {
                GalleryView().environment(\.horizontalSizeClass, horizontalSizeClass)
            }
            Tab("설정", systemImage: "keyboard", value: AppTab.settings) {
                SettingsView().environment(\.horizontalSizeClass, horizontalSizeClass)
            }
        }
        // Keep iPad navigation at the bottom while retaining each screen's actual size class.
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.activeAppTab, selectedTab)
        .environment(\.libraryHomeRequest, libraryHomeRequest)
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
        .alert("비교 버전을 다시 준비해 주세요", isPresented: $optimizationNotificationError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("알림의 비교 결과가 만료되었거나 앱 종료 후 사라졌어요. 팩에서 용량 최적화를 열어 비교 버전을 다시 만들어 주세요.")
        }
        .task(id: notifications.pendingOptimization?.id) {
            guard let destination = notifications.pendingOptimization else { return }
            // Wait for an active window and any unrelated sheet/alert to close.
            while !Task.isCancelled {
                let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }
                    .flatMap(\.windows).first(where: \.isKeyWindow)
                let presentingTarget = optimizations.presented?.id.uuidString == destination.sessionID
                if let window, UIApplication.shared.applicationState == .active,
                   !onboarding, imports.presentedImport == nil, linkInbox.received == nil,
                   (window.rootViewController?.presentedViewController == nil || presentingTarget) {
                    break
                }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            guard let session = optimizations.current, session.id.uuidString == destination.sessionID,
                  await session.openPreparedProfile(destination.profile) else {
                notifications.pendingOptimization = nil
                optimizationNotificationError = true
                return
            }
            guard !Task.isCancelled, notifications.pendingOptimization?.id == destination.id else { return }
            notifications.pendingOptimization = nil
            optimizations.presented = session
        }
        .task { onboarding = !hasCompletedOnboarding }
        .onChange(of: hasCompletedOnboarding) { _, complete in if !complete { onboarding = true } }
    }
}

#Preview { ContentView() }
