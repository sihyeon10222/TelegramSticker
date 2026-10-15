import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
            Button("데이터 삭제", systemImage: "trash", role: .destructive) { confirmDataDelete = true }
                .labelStyle(.iconOnly).buttonStyle(.glass).disabled(deletionDisabled || installed == 0)
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
            Button("캐시 삭제", systemImage: "eraser", action: clearCache)
                .labelStyle(.iconOnly).buttonStyle(.glass).disabled(deletionDisabled)
                .accessibilityIdentifier("clearCache")
        }
        HStack(spacing: 12) {
            if let current = OptimizationCenter.shared.current, !current.finished {
                Button { OptimizationCenter.shared.presentCurrent() } label: {
                    Text("최근 용량 최적화 다시 열기")
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .allowsTightening(true)
                }
                .buttonStyle(.glass)
                .layoutPriority(1)
            }
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
                message = nil
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
