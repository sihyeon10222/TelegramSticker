import SwiftUI

struct StorageSettingsView: View {
    @State private var installed: Int64 = 0
    @State private var disposable: Int64 = 0
    @State private var busy = true
    @State private var clearing = false
    @State private var optimization = false
    @State private var message: String?
    private var jobs: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportJobs") }
    var body: some View {
        LabeledContent("설치 데이터", value: ByteCountFormatter.string(fromByteCount: installed, countStyle: .file))
        LabeledContent("삭제 가능한 캐시", value: ByteCountFormatter.string(fromByteCount: disposable, countStyle: .file))
        HStack(spacing: 12) {
            Button("스티커 용량 최적화") { optimization = true }
                .disabled(clearing || (installed == 0 && OptimizationCenter.shared.current == nil))
                .accessibilityIdentifier("optimizeStorage")
            Spacer(minLength: 0)
            Button("캐시 삭제") {
                clearing = true
                Task {
                    defer { clearing = false }
                    do {
                        guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                        try await ImportJobCache.shared.clear(root: jobs, writer: writer)
                        message = "캐시를 삭제했어요. 설치한 팩과 연결 설정은 유지했어요."
                    } catch { message = error.localizedDescription }
                    await refresh()
                }
            }
            .disabled(busy || clearing || ImportActivity.shared.count > 0)
            .accessibilityIdentifier("clearCache")
        }
        .buttonStyle(.glass)
        .sheet(isPresented: $optimization) { OptimizationView(request: OptimizationRequest()) }
        .task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        if OptimizationCenter.shared.current != nil {
            Button("최근 최적화 다시 열기", systemImage: "arrow.up.forward.app") { OptimizationCenter.shared.presentCurrent() }
                .buttonStyle(.glass)
        }
        if busy || ImportActivity.shared.count > 0 { Text("가져오기·업데이트 작업 중에는 삭제할 수 없어요.").font(.caption).foregroundStyle(.secondary) }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary) }

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
            for job in (try? fm.contentsOfDirectory(at: jobs, includingPropertiesForKeys: nil)) ?? [] {
                if job.lastPathComponent == "draft.json" { disposable += Int64((try? job.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                else if job.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil { disposable += bytes(job) }
            }
            return (installed, disposable)
        }.value
        if let values { installed = values.0; disposable = values.1 }
    }
}
