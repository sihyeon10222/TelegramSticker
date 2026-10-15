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
