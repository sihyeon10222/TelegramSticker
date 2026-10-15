import Foundation

nonisolated struct WorkerConfiguration: Codable, Sendable {
    let origin: URL
    let accessKey: String
    init(address: String, accessKey: String) throws {
        guard let c = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "https", let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.port == nil, c.query == nil, c.fragment == nil, ["", "/"].contains(c.path),
              let url = c.url, (accessKey.isEmpty || (24...256).contains(accessKey.utf8.count)),
              accessKey.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }), !accessKey.contains(":") else {
            throw StickerImportError.invalidConfiguration
        }
        origin = url
        self.accessKey = accessKey
    }
}
