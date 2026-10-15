import Foundation
import Security

@MainActor enum ImportSettings {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.sihyeon.TelegramSticker.import", kSecAttrAccount as String: "worker"]
    static func load() throws -> WorkerConfiguration? {
        // Production service uses an automatically acquired, short-lived session.
        // Legacy Keychain configuration is retained but is no longer required or read.
        try WorkerConfiguration(address: "https://stickerbridge.stickerbridge-worker.workers.dev", accessKey: "")
    }

    static func save(_ config: WorkerConfiguration) throws {
        let data = try JSONEncoder().encode(config)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw StickerImportError.invalidConfiguration }
        } else if status != errSecSuccess { throw StickerImportError.invalidConfiguration }
    }
}
