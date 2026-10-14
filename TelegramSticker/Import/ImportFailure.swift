import Foundation

nonisolated struct ImportFailure: Codable, Identifiable, Sendable {
    let id: String
    let format: String
    let stage: String
    let code: String
    let message: String
    let retryable: Bool
    static func record(sticker: RemoteSticker, stage: String, error: Error) -> Self {
        var code = "conversion_failed", retryable = false
        var message = error.localizedDescription
        if let value = error as? StickerImportError {
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
        return Self(id: sticker.id, format: sticker.format, stage: stage, code: code, message: message, retryable: retryable)
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
