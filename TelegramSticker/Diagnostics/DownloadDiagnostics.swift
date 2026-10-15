import Foundation
import Observation

nonisolated enum DiagnosticContext {
    @TaskLocal static var operationID: UUID?
    @TaskLocal static var packName: String?
}

nonisolated struct DownloadLogEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let detail: String
    var operationID: UUID?
    var packName: String?
    var isIssue: Bool {
        detail.contains("FAIL") || detail.contains("실패") || detail.contains("errorType=") || detail.hasPrefix("CONVERSION")
    }
    var pack: String? {
        if let packName { return packName }
        for marker in ["pack=", "/v1/packs/"] {
            if let range = detail.range(of: marker) {
                return String(detail[range.upperBound...].prefix { !$0.isWhitespace && $0 != "/" && $0 != "?" })
            }
        }
        return nil
    }
}

nonisolated struct DownloadLogOperation: Codable, Identifiable {
    var id = UUID()
    var started = Date()
    var ended: Date?
    var title: String
    var outcome = "진행 중"
    var summary: String?
}

@MainActor @Observable
final class DownloadDiagnostics {
    static let shared = DownloadDiagnostics()
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("download-log.json")
    }
    private struct Archive: Codable {
        var operations: [DownloadLogOperation]
        var entries: [DownloadLogEntry]
    }
    private(set) var entries: [DownloadLogEntry] = []
    private(set) var operations: [DownloadLogOperation] = []
    private var pendingSave: Task<Void, Never>?
    private init() {
        guard let data = try? Data(contentsOf: Self.file) else { return }
        if let saved = try? JSONDecoder().decode(Archive.self, from: data) {
            entries = saved.entries; operations = saved.operations
            for index in operations.indices where operations[index].ended == nil && operations[index].outcome == "진행 중" {
                operations[index].ended = Date()
                operations[index].outcome = "중단 · 앱 종료"
            }
        } else if let legacy = try? JSONDecoder().decode([DownloadLogEntry].self, from: data), !legacy.isEmpty {
            let operation = DownloadLogOperation(started: legacy.first!.date, ended: legacy.last!.date,
                title: "이전 버전 로그", outcome: "이전 기록")
            operations = [operation]
            entries = legacy.map { var entry = $0; entry.operationID = operation.id; return entry }
        }
    }
    /// Task-local identity follows child tasks, keeping concurrent packs in their parent batch.
    func run(title: String, body: @MainActor () async -> Void) async {
        let operation = DownloadLogOperation(title: Self.redact(title))
        operations.append(operation)
        trim()
        persist()
        await DiagnosticContext.$operationID.withValue(operation.id) { await body() }
        if let index = operations.firstIndex(where: { $0.id == operation.id }), operations[index].ended == nil {
            operations[index].ended = Date()
            operations[index].outcome = Task.isCancelled ? "취소" : entries.contains { $0.operationID == operation.id && $0.isIssue } ? "종료 · 오류 확인" : "완료"
        }
        persist()
    }
    func finish(success: Bool, summary: String?, cancelled: Bool) {
        guard let id = DiagnosticContext.operationID,
              let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].ended = Date()
        operations[index].outcome = cancelled ? "취소" : success ? "완료" : "종료 · 오류 확인"
        operations[index].summary = summary.map(Self.redact)
        persist()
    }
    nonisolated static func redact(_ value: String) -> String {
        var result = value
        for pattern in ["(?i)Bearer[ \t]+[^ \r\n]+", "[0-9]{5,}:[A-Za-z0-9_-]{20,}"] {
            result = result.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        return result
    }
    nonisolated static func errorDetails(_ error: Error) -> String {
        let ns = error as NSError
        var result = "errorType=\(String(reflecting: type(of: error))) domain=\(ns.domain) code=\(ns.code) description=\(error.localizedDescription)"
        if let limit = error as? ImportLimitFailure { result += " " + limit.diagnostic }
        if let server = error as? StickerImportError, case let .server(code, retryable, after) = server {
            result += " serverCode=\(code) retryable=\(retryable) retryAfter=\(after)s"
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            result += " underlyingDomain=\(underlying.domain) underlyingCode=\(underlying.code) underlyingDescription=\(underlying.localizedDescription)"
        }
        return redact(result)
    }
    func record(_ detail: String) {
        let detail = Self.redact(detail)
        var operationID = DiagnosticContext.operationID
        if operationID == nil {
            let title = detail.hasPrefix("GALLERY") ? "갤러리 미리보기·목록" : "서비스·기타 진단"
            if let existing = operations.last(where: { $0.title == title && Date().timeIntervalSince($0.started) < 300 }) {
                operationID = existing.id
            } else {
                let operation = DownloadLogOperation(title: title, outcome: "진단 기록")
                operations.append(operation); operationID = operation.id
            }
        }
        entries.append(DownloadLogEntry(detail: detail, operationID: operationID, packName: DiagnosticContext.packName))
        // Bound each operation independently; one large pack cannot erase another operation.
        if let operationID {
            let ids = entries.filter { $0.operationID == operationID }
            if ids.count > 3000 {
                let removed = Set(ids.prefix(ids.count - 3000).map(\.id))
                entries.removeAll { removed.contains($0.id) }
            }
        }
        trim()
        // Coalesce bursts of HTTP/frame diagnostics rather than rewriting on every entry.
        if pendingSave == nil {
            pendingSave = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                pendingSave = nil; persist()
            }
        }
    }
    private func trim() {
        let completed = operations.filter { $0.ended != nil || $0.outcome == "진단 기록" }
        if completed.count > 40 {
            let removed = Set(completed.prefix(completed.count - 40).map(\.id))
            operations.removeAll { removed.contains($0.id) }
            entries.removeAll { $0.operationID.map(removed.contains) == true }
        }
    }
    func clear() {
        pendingSave?.cancel(); pendingSave = nil
        // Keep active identities so subsequent events still belong to the same work.
        operations.removeAll { $0.ended != nil || $0.outcome != "진행 중" }
        entries.removeAll(); persist()
    }
    var text: String { entries.map { "[\($0.date.ISO8601Format())] \($0.detail)" }.joined(separator: "\n") }
    func export(_ ids: Set<UUID>) -> String {
        operations.filter { ids.contains($0.id) }.map { operation in
            let header = "=== \(operation.title) | \(operation.outcome) | \(operation.started.ISO8601Format()) | id=\(operation.id) ===\n" + (operation.summary ?? "")
            return header + "\n" + entries.filter { $0.operationID == operation.id }.map {
                "[\($0.date.ISO8601Format())] \($0.detail)"
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
    private func persist() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Archive(operations: operations, entries: entries)) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }
}
