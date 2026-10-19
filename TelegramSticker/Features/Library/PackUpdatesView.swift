import SwiftUI

struct PackUpdatesRequest: Identifiable {
    let id = UUID()
    var packIDs: Set<String>? = nil
    var checkOnOpen = false
}

struct PackUpdatesView: View {
    let request: PackUpdatesRequest
    var onCheckCompleted: () -> Void = {}
    @State private var packs: [PackManifestV1] = []
    @State private var client: WorkerClient?
    @State private var applying: ImportModel?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var service: PackUpdateService { .shared }
    private var updates: [PackUpdateEntry] { packs.compactMap { service.entries[$0.id] }.filter { $0.difference.hasChanges } }
    private var failedPacks: [PackManifestV1] { packs.filter { service.errors[$0.id] != nil } }
    private var busy: Bool { service.isChecking || ImportActivity.shared.count > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if service.isChecking { ProgressView(service.status ?? "업데이트 확인 중") }
                    if let error { Text(error).foregroundStyle(.red) }
                    if updates.isEmpty, !service.isChecking {
                        Text(failedPacks.isEmpty ? "업데이트할 내용이 없어요." : "일부 팩을 확인하지 못했어요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(updates) { entry in
                        packCard(entry)
                    }
                    if !failedPacks.isEmpty {
                        DisclosureGroup("조회 실패 \(failedPacks.count)팩") {
                            ForEach(failedPacks) { pack in
                                Text("\(pack.title) · \(service.errors[pack.id] ?? "")")
                                    .font(.caption).foregroundStyle(.red)
                            }
                            Button("다시 확인") { Task { await service.check(packs: failedPacks) } }.disabled(busy)
                        }
                    }
                }.padding().frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("스티커 팩 업데이트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppModalCloseToolbar { dismiss() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("모두 업데이트") { apply(updates) }
                        .appGlassButton(prominent: true, tint: .blue)
                        .disabled(updates.isEmpty || busy || updates.contains { service.errors[$0.id] != nil })
                }
            }
            .refreshable { await service.check(packs: packs) }
            .sheet(item: $applying, onDismiss: { Task { await reload() } }) { ImportView(model: $0) }
            .onChange(of: ImportActivity.shared.libraryChangeID) { _, _ in Task { await reload() } }
            .task {
                do { if let configuration = try ImportSettings.load() { client = WorkerClient(configuration: configuration) } }
                catch { self.error = error.localizedDescription }
                await reload()
                if request.checkOnOpen {
                    await service.check(packs: packs)
                    onCheckCompleted()
                }
            }
        }.appModalBackground()
        .workNotificationScreen("packUpdates")
    }

    private func packCard(_ entry: PackUpdateEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.installed.title).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
                Button("업데이트") { apply([entry]) }
                    .appGlassButton(prominent: true, tint: .blue)
                    .disabled(busy || service.errors[entry.id] != nil)
            }
            if let failure = service.errors[entry.id] {
                Text("조회 실패 · " + failure).font(.caption).foregroundStyle(.red)
            }
            PackUpdateChangesView(entry: entry, client: client)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func reload() async {
        do {
            let all = try await Task.detached { try LibraryReader.shared().snapshot(resolvingFiles: false).packs }.value
            packs = all.filter { $0.telegramName != nil && (request.packIDs == nil || request.packIDs!.contains($0.id)) }
            await service.restore(packs: all)
        } catch { self.error = error.localizedDescription }
    }

    private func apply(_ entries: [PackUpdateEntry]) {
        Task {
            guard let writer = LibraryWriter.shared else { error = LibraryError.unavailable.localizedDescription; return }
            applying = await ImportModel.beginUpdates(entries, writer: writer)
            if applying == nil { error = "업데이트를 시작하지 못했어요. 진행 중인 작업과 연결 상태를 확인해 주세요." }
        }
    }
}
