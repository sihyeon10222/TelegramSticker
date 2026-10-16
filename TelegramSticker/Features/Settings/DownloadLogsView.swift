import SwiftUI
import UIKit

struct DownloadLogsView: View {
    @Environment(\.activeAppTab) private var activeTab
    @State private var selection = Set<UUID>()
    @State private var selecting = false
    @State private var copied = false
    private var store: DownloadDiagnostics { .shared }
    private var operations: [DownloadLogOperation] { Array(store.operations.reversed()) }
    var body: some View {
        List {
            Section {
                if operations.isEmpty { Text("아직 기록된 작업이 없어요.").foregroundStyle(.secondary) }
                ForEach(operations) { operation in
                    if selecting {
                        Button {
                            if !selection.insert(operation.id).inserted { selection.remove(operation.id) }
                        } label: {
                            HStack {
                                Image(systemName: selection.contains(operation.id) ? "checkmark.circle.fill" : "circle")
                                row(operation)
                            }
                        }.buttonStyle(.plain)
                    } else {
                        NavigationLink { DownloadOperationLogsView(id: operation.id) } label: { row(operation) }
                    }
                }
            } footer: {
                Text("최근 작업 40개를 보관해요. 작업을 열면 팩별 기록과 오류를 확인할 수 있어요. 각 작업의 상세 기록은 최근 3,000줄까지 유지해요.")
            }
        }
        .navigationTitle("다운로드 로그")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SelectionToggleButton(active: selecting, title: "선택") { selecting.toggle(); selection.removeAll(); copied = false }
                    .disabled(operations.isEmpty)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("비우기", role: .destructive) { store.clear(); selection.removeAll(); selecting = false }
                    .disabled(operations.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Spacer()
                    Button(copied ? "복사됨" : "작업 복사 (\(selection.count))") {
                        copyDiagnosticText(store.export(selection)); copied = true
                    }.disabled(selection.isEmpty)
                }.font(.subheadline).padding(12).background(.bar)
            }
        }
        .onChange(of: selection) { _, _ in copied = false }
        .onChange(of: activeTab) { _, tab in
            if tab != .settings { selecting = false; selection.removeAll(); copied = false }
        }
    }
    private func row(_ operation: DownloadLogOperation) -> some View {
        let logs = store.entries.filter { $0.operationID == operation.id }
        let issues = logs.filter(\.isIssue).count
        return VStack(alignment: .leading, spacing: 5) {
            Text(operation.title).font(.headline).lineLimit(2)
            HStack {
                Text(operation.outcome).foregroundStyle(issues > 0 ? Color.orange : Color.secondary)
                Spacer()
                Text(operation.started.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }.font(.caption)
            Text("상세 \(logs.count)줄 · 오류·재시도 \(issues)건").font(.caption).foregroundStyle(.secondary)
            if let summary = operation.summary { Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
}

private struct DownloadOperationLogsView: View {
    let id: UUID
    @State private var issuesOnly = false
    @State private var pack = ""
    @State private var copied = false
    private var store: DownloadDiagnostics { .shared }
    private var operation: DownloadLogOperation? { store.operations.first { $0.id == id } }
    private var entries: [DownloadLogEntry] { store.entries.filter { $0.operationID == id } }
    private var packs: [String] { Set(entries.compactMap(\.pack)).sorted() }
    private var filtered: [DownloadLogEntry] {
        entries.filter { (!issuesOnly || $0.isIssue) && (pack.isEmpty || $0.pack == pack) }
    }
    var body: some View {
        List {
            Section("작업 결과") {
                if let operation {
                    LabeledContent("상태", value: operation.outcome)
                    LabeledContent("시작", value: operation.started.ISO8601Format())
                    if let ended = operation.ended { LabeledContent("종료", value: ended.ISO8601Format()) }
                    if let summary = operation.summary { Text(summary).textSelection(.enabled) }
                } else { Text("기록이 삭제됐어요.") }
            }
            Section {
                Toggle("오류·재시도만 보기", isOn: $issuesOnly)
                if !packs.isEmpty {
                    Picker("팩", selection: $pack) {
                        Text("모든 팩").tag("")
                        ForEach(packs, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            Section("기술 로그 · \(filtered.count)줄") {
                if filtered.isEmpty { Text("조건에 맞는 기록이 없어요.").foregroundStyle(.secondary) }
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.date.ISO8601Format()).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(entry.detail).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                    .listRowSeparatorTint(entry.isIssue ? .orange : nil)
                    .contextMenu { Button("이 로그 복사") { copyDiagnosticText(entry.detail) } }
                }
            }
        }
        .navigationTitle(operation?.title ?? "작업 로그")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(copied ? "복사됨" : "복사") {
                    // Export the entire operation, including context hidden by a filter.
                    copyDiagnosticText(store.export([id])); copied = true
                }.disabled(operation == nil)
            }
        }
    }
}

@MainActor private func copyDiagnosticText(_ text: String) {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    UIPasteboard.general.string = "StickerBridge \(version) (\(build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)\n" + text
}
