import Foundation
import Security

@MainActor enum ImportSettings {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.sihyeon.TelegramSticker.import", kSecAttrAccount as String: "worker"]
    static func load() throws -> WorkerConfiguration? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StickerImportError.invalidConfiguration }
        let config = try JSONDecoder().decode(WorkerConfiguration.self, from: data)
        return try WorkerConfiguration(address: config.origin.absoluteString, accessKey: config.accessKey)
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
