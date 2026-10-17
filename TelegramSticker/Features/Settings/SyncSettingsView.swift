import SwiftUI

struct SyncSettingsView: View {
    @Bindable private var sync = LibrarySyncService.shared
    var body: some View {
        Section {
            Toggle("iCloud 동기화", isOn: Binding(get: { sync.enabled && LibraryChangeJournal.cloudKitConfigured }, set: { value in
                Task { await sync.setEnabled(value); SyncDownloadCoordinator.shared.reconcile(retryFailures: true) }
            })).disabled(!LibraryChangeJournal.cloudKitConfigured)
            if !sync.status.isEmpty { Text(sync.status).font(.footnote).foregroundStyle(.secondary) }
            if let date = sync.lastCompleted { LabeledContent("마지막 동기화", value: date.formatted(date: .abbreviated, time: .shortened)) }
            if sync.accountConfirmationRequired {
                Button("새 Apple 계정 연결") { confirmingAccount = true }
                    .confirmationDialog("현재 기기의 팩 목록을 새 Apple 계정과 합칠까요?", isPresented: $confirmingAccount, titleVisibility: .visible) {
                        Button("새 계정에 연결") { Task { await sync.confirmNewAccount(); SyncDownloadCoordinator.shared.reconcile(retryFailures: true) } }
                    } message: { Text("이전 계정의 전송 대기 변경은 새 계정으로 보내지 않습니다.") }
            }
            Button {
                Task { await sync.synchronize(); SyncDownloadCoordinator.shared.reconcile(retryFailures: true) }
            } label: {
                HStack { Text("지금 동기화"); if sync.isSyncing { ProgressView() } }
            }.disabled(!sync.enabled || sync.isSyncing || !LibraryChangeJournal.cloudKitConfigured)
        } header: { Text("iCloud") } footer: {
            Text("같은 Apple 계정의 팩 목록·순서·팩 삭제를 동기화합니다. 스티커 파일과 화질은 기기별로 관리하며 앱이 실행될 때 다운로드합니다.")
        }
    }
    @State private var confirmingAccount = false
}
