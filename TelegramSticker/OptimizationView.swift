import SwiftUI

struct OptimizationRequest: Identifiable {
    let id = UUID()
    var packIDs: Set<String>? = nil
    var stickerIDs: Set<String>? = nil
}

struct OptimizationView: View {
    let request: OptimizationRequest
    @State private var profile = StorageOptimizationProfile.balanced
    @State private var running = false
    @State private var applying = false
    @State private var finished = false
    @State private var dismissed = false
    @State private var message: String?
    @State private var progress = 0.0
    @State private var draft: PreparedOptimization?
    @State private var zoom = 1.0
    @State private var operation: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    private var jobs: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImportJobs") }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Picker("최적화 품질", selection: $profile) {
                        ForEach(StorageOptimizationProfile.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(running || finished)
                    Text("최대 \(profile.pixels)px · GIF 최대 \(profile.fps)fps. 작은 원본은 확대하지 않고, 더 작아진 파일만 적용해요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let draft {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("예상 절약 \(bytes(draft.saved))").font(.title2.bold())
                                .accessibilityIdentifier("optimizationSavings")
                            Text("팩 저장 용량 \(bytes(draft.before)) → \(bytes(draft.after))")
                            Text("\(draft.comparisons.count)개 비교 · \(draft.before == 0 ? 0 : Int(Double(draft.saved) / Double(draft.before) * 100))% 감소")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(draft.comparisons) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.original.detail + " · " + item.original.name).font(.headline)
                                HStack(spacing: 8) {
                                    comparison(item.original, title: "원본", size: item.before)
                                    comparison(item.optimized, title: "최적화", size: item.after)
                                }
                                .accessibilityIdentifier("optimizationComparison")
                                Text("이 항목 절약 \(bytes(max(0, item.before - item.after))) (PNG·GIF 합계)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                        if !draft.failures.isEmpty {
                            Text("기존 상태로 유지할 항목\n" + draft.failures.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !running {
                        Button("비교 버전 만들기") { start(apply: false) }
                            .buttonStyle(.glassProminent).disabled(ImportActivity.shared.count > 0)
                            .accessibilityIdentifier("prepareOptimization")
                    }
                    if running {
                        ProgressView(applying ? "최적화 버전 적용 중" : "원본을 보존하며 비교 버전 만드는 중", value: progress)
                        Button("중단") { operation?.cancel() }.buttonStyle(.glass)
                    }
                    if let notice = BackgroundWork.shared.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if let message { Text(message).accessibilityIdentifier("optimizationResult") }
                    Text("비교 버전을 만드는 동안 설치된 파일은 바뀌지 않아요. 투명도와 재생 길이는 유지하지만 세부 묘사와 움직임은 달라질 수 있어요. 적용 후 원본 복원은 팩 삭제 후 재설치가 필요해요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("optimizationList")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let draft, !draft.comparisons.isEmpty {
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                                Slider(value: $zoom, in: 1...3)
                                    .accessibilityLabel("모든 스티커 함께 확대")
                                    .accessibilityValue(String(format: "%.1f배", zoom))
                                    .accessibilityIdentifier("optimizationZoom")
                                Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
                                Text(String(format: "%.1f×", zoom)).font(.caption.monospacedDigit())
                            }
                            .padding(16)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                            if !finished {
                                Button { start(apply: true) } label: {
                                    Text("최적화 버전 \(draft.comparisons.count)개 일괄 적용")
                                        .frame(maxWidth: .infinity).lineLimit(1)
                                }
                                .buttonStyle(.glassProminent).controlSize(.large)
                                .disabled(running || draft.saved == 0 || ImportActivity.shared.count > 0)
                                .accessibilityIdentifier("applyOptimization")
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .navigationTitle("용량 최적화")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(running ? "작업 유지하고 닫기" : "닫기") { dismiss() }.accessibilityIdentifier("closeOptimization") } }
                .onChange(of: profile) { _, _ in clearDraft(); message = nil; zoom = 1 }
                .onDisappear { dismissed = true; if !running { clearDraft() } }
        }
    }
    private func bytes(_ size: Int64) -> String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    private func comparison(_ sticker: SampleSticker, title: String, size: Int64) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                StickerLargePreview(sticker: sticker, pixels: 512)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(zoom)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .id(sticker.id)
            Text(title).font(.subheadline.bold())
            Text(bytes(size)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private func clearDraft() {
        if let draft { try? FileManager.default.removeItem(at: draft.root) }
        draft = nil
    }
    private func start(apply: Bool) {
        guard !running, ImportActivity.shared.count == 0 else { return }
        running = true; applying = apply; progress = 0; message = nil
        operation = Task {
            ImportActivity.shared.count += 1
            let id = await BackgroundWork.shared.begin(title: apply ? "스티커 최적화 적용" : "스티커 최적화 비교 준비") { operation?.cancel() }
            var success = false
            defer {
                running = false; ImportActivity.shared.count -= 1
                BackgroundWork.shared.end(id: id, success: success)
                if dismissed { clearDraft() }
            }
            do {
                guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
                let report: @Sendable (Int, Int) -> Void = { done, total in
                    Task { @MainActor in
                        progress = Double(done) / Double(max(1, total))
                        BackgroundWork.shared.report(id: id, completed: Int64(done), total: Int64(total + 1), subtitle: "처리 \(done)/\(total)")
                    }
                }
                if apply, let draft {
                    let result = try await ImportJobCache.shared.applyOptimization(root: jobs, writer: writer, draft: draft, progress: report)
                    success = result.failures.isEmpty; finished = true
                    message = "\(result.optimizedPacks)개 팩 반영 · \(bytes(result.saved)) 절약" + (result.failures.isEmpty ? "" : "\n" + result.failures.joined(separator: "\n"))
                } else {
                    draft = try await ImportJobCache.shared.prepareOptimization(root: jobs, writer: writer,
                        packIDs: request.packIDs, stickerIDs: request.stickerIDs, profile: profile, progress: report)
                    success = true
                    if draft?.saved == 0 { message = "현재 품질에서는 더 줄일 용량이 없어요. 원본을 유지해요." }
                }
            } catch { message = error is CancellationError ? "중단했어요. 완료된 팩은 유지하고, 처리 중인 팩의 기존 파일은 보존해요." : error.localizedDescription }
        }
    }
}
