import SwiftUI

struct OptimizationView: View {
    @Bindable private var model: OptimizationSession
    @Environment(\.dismiss) private var dismiss
    init(request: OptimizationRequest) { _model = Bindable(wrappedValue: OptimizationCenter.shared.session(for: request)) }
    init(model: OptimizationSession) { _model = Bindable(wrappedValue: model) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("최대 256px · GIF 최대 15fps로 최적화해 바로 적용해요. 작은 원본은 확대하지 않고, 더 작아진 파일만 적용해요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if model.running {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("용량 최적화 중").font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(model.progress * 100))%").monospacedDigit()
                            Button("중단") { model.cancel() }.appGlassButton()
                        }
                        ProgressView(value: model.progress)
                    }
                    if let message = model.message { Text(message).accessibilityIdentifier("optimizationResult") }
                    if !model.running {
                        if !model.finished {
                            Button("다시 시도") { model.start() }.appGlassButton(prominent: true)
                                .disabled(ImportActivity.shared.count > 0)
                        }
                        if !model.sourceLinks.isEmpty {
                            Button("Telegram 원본으로 복원", systemImage: "arrow.uturn.backward") { model.restoreOriginals() }
                                .appGlassButton().disabled(ImportActivity.shared.count > 0)
                        }
                    }
                    Text("원본 복원은 저장된 Telegram 링크에서 다시 받아 교체하며, 준비가 끝날 때까지 현재 팩을 유지해요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("optimizationList")
            .navigationTitle("용량 최적화").navigationBarTitleDisplayMode(.inline)
            .modifier(KeyboardPermissionReminder(working: model.running))
            .toolbar { AppModalCloseToolbar(title: model.running ? "작업 유지하고 닫기" : "닫기", accessibilityID: "closeOptimization") { dismiss() } }
            .sheet(item: $model.restoreImport) { ImportView(model: $0) }
            .onAppear { model.start() }
        }
        .appModalBackground()
        .workNotificationScreen("optimization:" + model.id.uuidString)
    }
}
