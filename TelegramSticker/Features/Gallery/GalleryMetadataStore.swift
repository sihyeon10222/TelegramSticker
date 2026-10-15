import Foundation
import Observation
import CryptoKit

actor GalleryMetadataStore {
    static let shared = GalleryMetadataStore()
    private var values: [String: (RemotePack, Date)] = [:]
    func pack(name: String, client: WorkerClient) async throws -> RemotePack {
        if let cached = values[name], Date().timeIntervalSince(cached.1) < 600 { return cached.0 }
        let pack = try await client.pack(name: name)
        values[name] = (pack, Date())
        if values.count > 200 { values = [name: (pack, Date())] }
        return pack
    }
    func clear() { values.removeAll() }
}
