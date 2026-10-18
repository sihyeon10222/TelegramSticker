import SwiftUI
import Combine
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
private struct LibraryUpdatesRequestKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    var libraryHomeRequest: Int {
        get { self[LibraryHomeRequestKey.self] }
        set { self[LibraryHomeRequestKey.self] = newValue }
    }
    var libraryUpdatesRequest: Int {
        get { self[LibraryUpdatesRequestKey.self] }
        set { self[LibraryUpdatesRequestKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.library
    @State private var libraryHomeRequest = 0
    @State private var libraryUpdatesRequest = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboarding = false
    @Bindable private var imports = ImportActivity.shared
    @Bindable private var optimizations = OptimizationCenter.shared
    @Bindable private var notifications = WorkNotifications.shared
    @State private var optimizationNotificationError = false
    @Bindable private var linkInbox = PackLinkInbox.shared
    var body: some View {
        navigation
        // Keep iPad navigation at the bottom while retaining each screen's actual size class.
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.activeAppTab, selectedTab)
        #if targetEnvironment(macCatalyst)
        .onReceive(NotificationCenter.default.publisher(for: .macOpenManagement)) { _ in selectedTab = .settings }
        #endif
        .environment(\.libraryHomeRequest, libraryHomeRequest)
        .environment(\.libraryUpdatesRequest, libraryUpdatesRequest)
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
        } message: { Text("이번에 받은 스티커만 화질을 비교하고 최적화해요. 기존 스티커는 유지해요.") }
        .sheet(item: $linkInbox.received) { ReceivedPackLinksView(received: $0) }
        .fileImporter(isPresented: $linkInbox.showFileImporter, allowedContentTypes: [UTType(filenameExtension: "stickerlinks") ?? .plainText, .plainText]) { result in
            switch result {
            case .success(let url): Task { await linkInbox.open(url) }
            case .failure(let error): linkInbox.error = error.localizedDescription
            }
        }
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
        .task(id: notifications.pendingPackUpdates) {
            guard notifications.pendingPackUpdates else { return }
            while !Task.isCancelled {
                let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
                if let window, UIApplication.shared.applicationState == .active, !onboarding,
                   window.rootViewController?.presentedViewController == nil { break }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            selectedTab = .library
            libraryHomeRequest += 1
            libraryUpdatesRequest += 1
            notifications.pendingPackUpdates = false
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await LibrarySyncService.shared.synchronize()
            SyncDownloadCoordinator.shared.reconcile(retryFailures: true)
            await resumeMacImportIfNeeded()
            // Foreground refresh also covers systems where CloudKit pushes are unavailable.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await LibrarySyncService.shared.synchronize()
                SyncDownloadCoordinator.shared.reconcile()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LibraryChangeJournal.notification).receive(on: RunLoop.main)) { _ in
            Task { await LibrarySyncService.shared.synchronize() }
        }
        .onChange(of: LibrarySyncService.shared.changeID) { _, _ in SyncDownloadCoordinator.shared.reconcile() }
        .onChange(of: hasCompletedOnboarding) { _, complete in if !complete { onboarding = true } else { Task { await resumeMacImportIfNeeded() } } }
    }
    private var navigation: some View {
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
    }
    private func resumeMacImportIfNeeded() async {
        #if targetEnvironment(macCatalyst)
        guard hasCompletedOnboarding, imports.count == 0, imports.current == nil, let writer = LibraryWriter.shared else { return }
        let model = ImportModel(writer: writer)
        _ = await model.resumePendingDownload()
        #endif
    }
}

#Preview { ContentView() }
