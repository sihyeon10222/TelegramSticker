import SwiftUI

struct StorageSettingsView: View {
    @State private var installed: Int64 = 0
    @State private var disposable: Int64 = 0
    @State private var busy = true
    @State private var clearing = false
    @State private var optimization = false
    @State private var message: String?
    @State private var confirmDataDelete = false
    private var jobs: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportJobs") }
    private var deletionDisabled: Bool { busy || clearing || ImportActivity.shared.count > 0 || OptimizationCenter.shared.current?.running == true }
    var body: some View {
        HStack(spacing: 12) {
            Text("설치 데이터")
            Spacer(minLength: 0)
            Text(ByteCountFormatter.string(fromByteCount: installed, countStyle: .file)).foregroundStyle(.secondary)
            Button("데이터 삭제", role: .destructive) { confirmDataDelete = true }
                .buttonStyle(.glass).disabled(deletionDisabled || installed == 0)
                .accessibilityIdentifier("deleteInstalledData")
                .confirmationDialog("설치한 스티커 팩을 모두 삭제할까요?", isPresented: $confirmDataDelete, titleVisibility: .visible) {
                    Button("설치 데이터 삭제", role: .destructive) { deleteInstalledData() }
                    Button("취소", role: .cancel) { }
                } message: { Text("설치한 팩이 앱과 키보드에서 삭제돼요. 앱 설정은 유지돼요.") }
        }
        HStack(spacing: 12) {
            Text("삭제 가능한 캐시")
            Spacer(minLength: 0)
            Text(ByteCountFormatter.string(fromByteCount: disposable, countStyle: .file)).foregroundStyle(.secondary)
            Button("캐시 삭제", action: clearCache)
                .buttonStyle(.glass).disabled(deletionDisabled)
                .accessibilityIdentifier("clearCache")
        }
        HStack(spacing: 12) {
            Text("작업 중에는 삭제할 수 없어요.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("스티커 용량 최적화") { optimization = true }
                .buttonStyle(.glass).fixedSize(horizontal: true, vertical: false)
                .disabled(clearing || (installed == 0 && OptimizationCenter.shared.current == nil))
                .accessibilityIdentifier("optimizeStorage")
        }
        .sheet(isPresented: $optimization) { OptimizationView(request: OptimizationRequest()) }
        .task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        if OptimizationCenter.shared.current != nil {
            HStack {
                Spacer(minLength: 0)
                Button("최근 용량 최적화 다시 열기", systemImage: "arrow.up.forward.app") { OptimizationCenter.shared.presentCurrent() }
                    .buttonStyle(.glass)
            }
        }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
    private func invalidateOptimization(deleteFiles: Bool = true) {
        OptimizationCenter.shared.current?.removeDrafts(deleteFiles: deleteFiles)
        OptimizationCenter.shared.current = nil
        OptimizationCenter.shared.presented = nil
    }
    private func clearCache() {
        guard !deletionDisabled else { return }
        clearing = true
        invalidateOptimization(deleteFiles: false)
        ImportActivity.shared.count += 1
        Task {
            defer { clearing = false; ImportActivity.shared.count -= 1 }
            do {
                guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                try await ImportJobCache.shared.clear(root: jobs, writer: writer)
                message = "캐시를 정리했어요. 설치한 팩과 설정은 유지했어요."
            } catch { message = error.localizedDescription }
            await refresh()
        }
    }
    private func deleteInstalledData() {
        guard !deletionDisabled else { return }
        clearing = true
        invalidateOptimization()
        ImportActivity.shared.count += 1
        Task {
            defer { clearing = false; ImportActivity.shared.count -= 1 }
            do {
                guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                try await ImportJobCache.shared.deleteInstalledData(root: jobs, writer: writer)
                ImportActivity.shared.current = nil
                ImportActivity.shared.optimizationSuggestion = nil
                message = "설치한 스티커 팩을 모두 삭제했어요."
            } catch { message = error.localizedDescription }
            ImportActivity.shared.libraryChangeID += 1
            await refresh()
        }
    }
    private func refresh() async {
        busy = await ImportJobCache.shared.isActive(root: jobs)
        let jobs = jobs
        let values = await Task.detached { () -> (Int64, Int64)? in
            guard let reader = try? LibraryReader.shared(), let snapshot = try? reader.snapshot(), snapshot.warnings.isEmpty else { return nil }
            func bytes(_ url: URL) -> Int64 {
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                var total: Int64 = 0
                while let file = enumerator?.nextObject() as? URL {
                    guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { continue }
                    if values.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
                    if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
                }
                return total
            }
            let index = try? reader.index()
            let installed = (index?.packs ?? []).reduce(Int64(0)) { sum, ref in
                sum + bytes(reader.root.appendingPathComponent(ref.manifestPath).deletingLastPathComponent())
            }
            let fm = FileManager.default
            let keep = Set((index?.packs ?? []).map { String($0.manifestPath.dropLast("/manifest.json".count)) })
            var disposable = bytes(reader.root.appendingPathComponent("staging"))
            for pack in (try? fm.contentsOfDirectory(at: reader.root.appendingPathComponent("packs"), includingPropertiesForKeys: nil)) ?? [] {
                for revision in (try? fm.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil)) ?? [] {
                    let relative = "packs/\(pack.lastPathComponent)/\(revision.lastPathComponent)"
                    if !keep.contains(relative), (try? reader.file(relative)) != nil { disposable += bytes(revision) }
                }
            }
            disposable += bytes(jobs)
            disposable += AppDisposableCache.bytes()
            return (installed, disposable)
        }.value
        if let values { installed = values.0; disposable = values.1 }
    }
}


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
            } message: { Text("설치한 모든 팩, 다운로드 기록, 캐시와 앱 설정이 삭제됩니다.") }
            .alert("모든 앱 데이터를 삭제할까요?", isPresented: $finalConfirm) {
                Button("모두 삭제하고 초기화", role: .destructive) { reset() }
                Button("취소", role: .cancel) {}
            } message: { Text("되돌릴 수 없습니다. iOS의 키보드 추가·전체 접근·알림 권한 설정은 유지됩니다.") }
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
                guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                OptimizationCenter.shared.current?.removeDrafts(deleteFiles: false)
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
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            } catch { self.error = error.localizedDescription; ImportActivity.shared.libraryChangeID += 1 }
        }
    }
}
