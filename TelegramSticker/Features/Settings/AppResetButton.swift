import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AppResetButton: View {
    @State private var confirm = false
    @State private var finalConfirm = false
    @State private var resetting = false
    @State private var error: String?
    var body: some View {
        Button("앱 초기화하기", role: .destructive) { confirm = true }
            .disabled(resetting || ImportActivity.shared.count > 0)
            .confirmationDialog("앱을 처음 설치한 상태로 초기화할까요?", isPresented: $confirm, titleVisibility: .visible) {
                Button("초기화 계속", role: .destructive) { finalConfirm = true }
                Button("취소", role: .cancel) {}
            } message: { Text("이 기기의 팩, 다운로드 기록, 캐시와 앱 설정을 삭제하고 동기화를 끕니다. iCloud와 다른 기기의 팩은 유지됩니다.") }
            .alert("모든 앱 데이터를 삭제할까요?", isPresented: $finalConfirm) {
                Button("모두 삭제하고 초기화", role: .destructive) { reset() }
                Button("취소", role: .cancel) {}
            } message: { Text("되돌릴 수 없습니다. 시스템의 키보드·알림 권한 설정은 유지됩니다.") }
            .alert("초기화 확인 필요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(error ?? "") }
        if resetting { ProgressView("초기화 중") }
    }
    private func reset() {
        guard ImportActivity.shared.count == 0, OptimizationCenter.shared.current?.running != true else { return }
        resetting = true
        // Block all work entry points until deletion completes.
        ImportActivity.shared.count += 1
        Task {
            defer { resetting = false; ImportActivity.shared.count -= 1 }
            do {
                await LibrarySyncService.shared.stopForReset()
                try await PackUpdateService.shared.reset()
                WorkNotifications.shared.pendingPackUpdates = false
                SyncDownloadCoordinator.shared.reconcile()
                guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                OptimizationCenter.shared.current = nil; OptimizationCenter.shared.presented = nil
                let jobs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportJobs")
                try await ImportJobCache.shared.reset(root: jobs, writer: writer)
                ImportSettings.reset()
                await WorkerClient.resetServiceSession()
                GalleryCatalogStore.shared.reset()
                DownloadDiagnostics.shared.clear()
                ImportActivity.shared.current = nil; ImportActivity.shared.presentedImport = nil
                PackLinkInbox.shared.received = nil; PackLinkInbox.shared.error = nil
                if let bundle = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundle) }
                let group = UserDefaults(suiteName: LibraryReader.appGroup)
                group?.removePersistentDomain(forName: LibraryReader.appGroup)
                group?.set(UUID().uuidString, forKey: "appResetEpoch")
                ImportActivity.shared.libraryChangeID += 1
                UserDefaults.standard.set(false, forKey: LibraryChangeJournal.enabledKey)
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            } catch { self.error = error.localizedDescription; ImportActivity.shared.libraryChangeID += 1 }
        }
    }
}
