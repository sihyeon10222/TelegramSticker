import Foundation
import Observation

/// Distinguishes service byte limits from parser/decode budgets without weakening validation.
nonisolated struct ImportLimitFailure: Error, LocalizedError, Sendable {
    let check: String
    let actual: String
    let limit: String
    var errorDescription: String? { "제한 검사 실패: \(check) (실제 \(actual), 허용 \(limit))" }
    var diagnostic: String { "check=\(check) actual=\(actual) limit=\(limit)" }
}

nonisolated struct ImportFailure: Codable, Identifiable, Sendable {
    let id: String
    let format: String
    let stage: String
    let code: String
    let message: String
    let retryable: Bool
    var technicalDetails: String? = nil
    static func record(sticker: RemoteSticker, stage: String, error: Error) -> Self {
        var code = "conversion_failed", retryable = false
        var message = error.localizedDescription
        if let value = error as? ImportLimitFailure {
            code = "limit_" + value.check
        } else if let value = error as? StickerImportError {
            switch value {
            case .server(let value, let retry, _): code = value; retryable = retry
            case .network: code = "network"; retryable = true
            case .conversionTimeout: code = "conversion_timeout"; retryable = true
            case .unsupportedFormat: code = "unsupported_or_damaged"
            case .tooLarge: code = "service_or_decode_limit"
            default: code = "invalid_response"
            }
        } else if case WebMContainerFailure.timing = error {
            code = "webm_timing"
        } else if case WebMContainerFailure.unsupported(let stage) = error {
            code = "webm_container_" + stage
        } else if let value = error as? WebMConversionFailure {
            code = "webm_\(value)"; retryable = value == .deadline
        } else {
            let ns = error as NSError
            if (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError) ||
                (ns.domain == NSPOSIXErrorDomain && ns.code == 28) {
                code = "disk_full"; message = "기기 저장 공간이 부족해요. 공간을 확보한 뒤 다시 시도해 주세요."; retryable = true
            } else if stage == "저장" { code = "file_write" }
        }
        return Self(id: sticker.id, format: sticker.format, stage: stage, code: code, message: message, retryable: retryable,
            technicalDetails: "stickerID=\(sticker.id) format=\(sticker.format) declaredSize=\(sticker.fileSize.map(String.init) ?? "unknown") dimensions=\(sticker.width)x\(sticker.height) stage=\(stage) retryable=\(retryable) " + DownloadDiagnostics.errorDetails(error))
    }
}

actor ImportFailureStore {
    static let shared = ImportFailureStore()
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ImportFailures")
    func load(name: String) -> [ImportFailure] {
        guard StickerLink.validName(name), let data = try? Data(contentsOf: root.appendingPathComponent(name + ".json")) else { return [] }
        return (try? JSONDecoder().decode([ImportFailure].self, from: data)) ?? []
    }
    func save(name: String, failures: [ImportFailure]) throws {
        guard StickerLink.validName(name) else { throw StickerImportError.invalidLink }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(failures).write(to: root.appendingPathComponent(name + ".json"), options: .atomic)
    }
}

nonisolated struct DownloadLogEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let detail: String
}

@MainActor @Observable
final class DownloadDiagnostics {
    static let shared = DownloadDiagnostics()
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("download-log.json")
    }
    var entries: [DownloadLogEntry] = []
    private init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([DownloadLogEntry].self, from: data) { entries = saved }
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
        entries.append(DownloadLogEntry(detail: Self.redact(detail)))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        persist()
    }
    func clear() { entries.removeAll(); persist() }
    var text: String { entries.map { "[\($0.date.formatted(date: .omitted, time: .standard))] \($0.detail)" }.joined(separator: "\n") }
    private func persist() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: Self.file, options: .atomic) }
    }
}
