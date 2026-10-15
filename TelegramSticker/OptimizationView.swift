import SwiftUI

struct OptimizationRequest: Identifiable {
    let id = UUID()
    var packIDs: Set<String>? = nil
    var stickerIDs: Set<String>? = nil
}

@MainActor @Observable
final class OptimizationCenter {
    static let shared = OptimizationCenter()
    var current: OptimizationSession?
    var presented: OptimizationSession?
    func session(for request: OptimizationRequest) -> OptimizationSession {
        if let current, current.running || (current.request.packIDs == request.packIDs && current.request.stickerIDs == request.stickerIDs) { return current }
        current?.removeDrafts()
        let session = OptimizationSession(request: request)
        current = session
        return session
    }
    func presentCurrent() { presented = current }
}

@MainActor @Observable
final class OptimizationSession: Identifiable {
    let id = UUID()
    let request: OptimizationRequest
    var profile = StorageOptimizationProfile.compact
    var running = false
    var applying = false
    var finished = false
    var message: String?
    var progress = 0.0
    var zoom = 1.0
    var restoreImport: ImportModel?
    var sourceLinks: [String] = []
    private var drafts: [StorageOptimizationProfile: PreparedOptimization] = [:]
    private var operation: Task<Void, Never>?
    private var progressGeneration = UUID()
    var draft: PreparedOptimization? { drafts[profile] }
    private var jobs: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportJobs") }
    init(request: OptimizationRequest) {
        self.request = request
        if let reader = try? LibraryReader.shared(), let snapshot = try? reader.snapshot(resolvingFiles: false) {
            sourceLinks = snapshot.packs.filter { request.packIDs == nil || request.packIDs!.contains($0.id) }
                .compactMap { $0.telegramName.map { "https://t.me/addstickers/" + $0 } }
        }
    }
    func removeDrafts(deleteFiles: Bool = true) {
        guard !running else { return }
        let roots = drafts.values.map(\.root)
        drafts.removeAll()
        if deleteFiles { Self.discard(roots) }
    }
    func selectProfile() {
        guard !running, !finished else { return }
        message = nil
        guard let cached = draft, let writer = LibraryWriter.shared else { return }
        let selected = profile
        Task {
            for original in cached.originals {
                if (try? await writer.hasRevision(id: original.id, revision: original.revision)) != true {
                    // Only invalidate the stale profile, keeping the other cached result.
                    if drafts[selected]?.root == cached.root {
                        drafts.removeValue(forKey: selected)
                        Self.discard([cached.root])
                    }
                    if profile == selected { message = "팩이 변경되어 이 비교 버전을 다시 만들어야 해요." }
                    return
                }
            }
        }
    }
    private static func discard(_ roots: [URL]) {
        Task.detached(priority: .utility) {
            for root in roots { try? FileManager.default.removeItem(at: root) }
        }
    }
    func cancel() { operation?.cancel() }
    func start(apply: Bool) {
        guard !running, ImportActivity.shared.count == 0 else { return }
        if !apply, draft != nil { return }
        guard !apply || draft != nil else { return }
        let selectedProfile = profile
        let selectedDraft = draft
        running = true; applying = apply; progress = 0; message = nil
        let generation = UUID(); progressGeneration = generation
        ImportActivity.shared.count += 1
        operation = Task {
            let id = await BackgroundWork.shared.begin(kind: apply ? .optimizationApply : .optimizationPreparation, title: apply ? "스티커 용량 최적화 적용" : "스티커 용량 최적화 비교 준비") { self.cancel() }
            var success = false
            defer {
                running = false; ImportActivity.shared.count -= 1
                BackgroundWork.shared.end(id: id, success: success, detail: message, cancelled: Task.isCancelled)
            }
            do {
                guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                let report: @Sendable (Int, Int) -> Void = { done, total in
                    Task { @MainActor in
                        guard self.running, self.progressGeneration == generation else { return }
                        self.progress = min(0.99, Double(done) / Double(max(1, total)))
                        BackgroundWork.shared.report(id: id, completed: Int64(done), total: Int64(max(1, total)), subtitle: "처리 \(done)/\(total) · \(Int(self.progress * 100))%")
                    }
                }
                if apply, let selectedDraft {
                    let result = try await ImportJobCache.shared.applyOptimization(root: jobs, writer: writer, draft: selectedDraft, progress: report)
                    success = result.failures.isEmpty; finished = true; progress = success ? 1 : min(progress, 0.99)
                    ImportActivity.shared.libraryChangeID += 1
                    message = "\(result.optimizedPacks)개 팩 반영 · \(ByteCountFormatter.string(fromByteCount: result.saved, countStyle: .file)) 절약" + (result.failures.isEmpty ? "" : "\n" + result.failures.joined(separator: "\n"))
                    // The source revisions changed; other profiles must not overwrite them.
                    let obsolete = drafts.filter { $0.key != selectedProfile }.values.map(\.root)
                    drafts = [selectedProfile: selectedDraft]
                    Self.discard(obsolete)
                } else {
                    let prepared = try await ImportJobCache.shared.prepareOptimization(root: jobs, writer: writer,
                        packIDs: request.packIDs, stickerIDs: request.stickerIDs, profile: selectedProfile, progress: report)
                    drafts[selectedProfile] = prepared
                    success = true; progress = 1
                    if prepared.saved == 0 { message = "현재 품질에서는 더 줄일 용량이 없어요. 원본을 유지해요." }
                }
                progressGeneration = UUID()
                if success { BackgroundWork.shared.report(id: id, completed: 1, total: 1, subtitle: apply ? "용량 최적화 적용 완료 · 100%" : "비교 준비 완료 · 100%", finalized: true) }
            } catch {
                progressGeneration = UUID()
                message = error is CancellationError ? "중단했어요. 완료된 팩은 유지하고, 처리 중인 팩의 기존 파일은 보존해요." : error.localizedDescription
            }
        }
    }
    func newComparison() { removeDrafts(); finished = false; message = nil; progress = 0 }
    func restoreOriginals() {
        guard !running, ImportActivity.shared.count == 0, !sourceLinks.isEmpty, let writer = LibraryWriter.shared else { return }
        operation = Task {
            let model = ImportModel(writer: writer)
            model.updating = true
            model.restoringOriginal = true
            await model.configure()
            guard ImportActivity.shared.count == 0 else { return }
            model.link = sourceLinks[0]
            model.additionalLinks = sourceLinks.dropFirst().map { var entry = AdditionalPackLink(); entry.value = $0; return entry }
            restoreImport = model
            model.downloadBatch()
            // Comparisons refer to the previous optimized revisions. The installed
            // files remain untouched until original downloads are fully prepared.
            newComparison()
        }
    }
}

struct OptimizationView: View {
    @Bindable private var model: OptimizationSession
    @Environment(\.dismiss) private var dismiss
    init(request: OptimizationRequest) { _model = Bindable(wrappedValue: OptimizationCenter.shared.session(for: request)) }
    init(model: OptimizationSession) { _model = Bindable(wrappedValue: model) }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Picker("용량 최적화 품질", selection: $model.profile) {
                        ForEach(StorageOptimizationProfile.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.running || model.finished)
                    Text("최대 \(model.profile.pixels)px · GIF 최대 \(model.profile.fps)fps. 작은 원본은 확대하지 않고, 더 작아진 파일만 적용해요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let draft = model.draft {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("예상 절약 \(bytes(draft.saved))").font(.title2.bold()).accessibilityIdentifier("optimizationSavings")
                            Text("팩 저장 용량 \(bytes(draft.before)) → \(bytes(draft.after))")
                            Text("\(draft.comparisons.count)개 비교 · \(draft.before == 0 ? 0 : Int(Double(draft.saved) / Double(draft.before) * 100))% 감소")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(draft.comparisons) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.original.detail + " · " + item.original.name).font(.headline)
                                HStack(spacing: 8) {
                                    comparison(item.original, title: "원본", size: item.before)
                                    comparison(item.optimized, title: "용량 최적화", size: item.after)
                                }.accessibilityIdentifier("optimizationComparison")
                                Text("이 항목 절약 \(bytes(max(0, item.before - item.after))) (PNG·GIF 합계)").font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                        if !draft.failures.isEmpty { Text(draft.failures.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary) }
                    } else if !model.running {
                        Button("비교 버전 만들기") { model.start(apply: false) }
                            .buttonStyle(.glassProminent).disabled(ImportActivity.shared.count > 0).accessibilityIdentifier("prepareOptimization")
                    }
                    if let message = model.message { Text(message).accessibilityIdentifier("optimizationResult") }
                    Text("화질별 비교 결과는 앱을 사용하는 동안 보관해요. 화면을 닫거나 품질을 바꿔도 다시 열 수 있어요. 원본 복원은 저장된 Telegram 링크에서 다시 받아 교체하며, 준비가 끝날 때까지 현재 팩을 유지해요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("optimizationList")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 10) {
                        if model.running || model.message != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                if model.running {
                                    HStack {
                                        ProgressView().controlSize(.small)
                                        Text(model.applying ? "용량 최적화 버전 적용 중" : "비교 버전 만드는 중").font(.subheadline.bold())
                                        Spacer()
                                        Text("\(Int(model.progress * 100))%").monospacedDigit()
                                        Button("중단") { model.cancel() }.buttonStyle(.glass)
                                    }
                                    ProgressView(value: model.progress)
                                } else if let message = model.message { Text(message).font(.caption).lineLimit(3) }
                            }.padding(12).frame(maxWidth: .infinity)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                        }
                        if let draft = model.draft, !draft.comparisons.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "minus.magnifyingglass")
                                Slider(value: $model.zoom, in: 1...3).accessibilityLabel("모든 스티커 함께 확대").accessibilityIdentifier("optimizationZoom")
                                Image(systemName: "plus.magnifyingglass")
                                Text(String(format: "%.1f×", model.zoom)).font(.caption.monospacedDigit())
                            }.padding(16).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                            if !model.finished {
                                Button { model.start(apply: true) } label: {
                                    Text("용량 최적화 버전 \(draft.comparisons.count)개 일괄 적용").frame(maxWidth: .infinity).lineLimit(1)
                                }.buttonStyle(.glassProminent).controlSize(.large)
                                    .disabled(model.running || draft.saved == 0 || ImportActivity.shared.count > 0).accessibilityIdentifier("applyOptimization")
                            }
                        }
                        if !model.running {
                            HStack {
                                if !model.sourceLinks.isEmpty {
                                    Button("Telegram 원본으로 복원", systemImage: "arrow.uturn.backward") { model.restoreOriginals() }
                                        .disabled(ImportActivity.shared.count > 0)
                                }
                                if model.finished { Button("새 비교") { model.newComparison() } }
                            }.font(.subheadline).buttonStyle(.glass)
                        }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .navigationTitle("용량 최적화").navigationBarTitleDisplayMode(.inline)
            .modifier(KeyboardPermissionReminder(working: model.running))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.running ? "작업 유지하고 닫기" : "닫기") { dismiss() }.accessibilityIdentifier("closeOptimization") } }
            .sheet(item: $model.restoreImport) { ImportView(model: $0) }
            .onAppear { model.selectProfile() }
            .onChange(of: model.profile) { _, _ in model.selectProfile() }
        }
    }
    private func bytes(_ size: Int64) -> String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    private func comparison(_ sticker: SampleSticker, title: String, size: Int64) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                StickerLargePreview(sticker: sticker, pixels: 512).frame(width: geometry.size.width, height: geometry.size.height).scaleEffect(model.zoom)
            }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 12))
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12)).id(sticker.id)
            Text(title).font(.subheadline.bold())
            Text(bytes(size)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
