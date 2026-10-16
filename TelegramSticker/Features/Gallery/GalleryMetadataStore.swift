import Foundation
import CryptoKit

/// Durable card metadata lets cached PNG/GIF previews open without a server round trip.
actor GalleryMetadataStore {
    static let shared = GalleryMetadataStore()
    nonisolated private struct Saved: Codable { let pack: RemotePack; let date: Date }
    private var values: [String: Saved] = [:]
    private var generation = 0
    private var suspended = false
    private var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GalleryPreviews/v1")
    }
    private func file(_ name: String) -> URL {
        let key = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("metadata-" + key + ".json")
    }
    nonisolated static func savedPack(name: String) -> RemotePack? {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GalleryPreviews/v1")
        let key = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = root.appendingPathComponent("metadata-" + key + ".json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024,
              let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data),
              (try? saved.pack.validate(requestedName: name)) != nil else { return nil }
        return saved.pack
    }
    private func saved(name: String) -> Saved? {
        if let value = values[name] { return value }
        let url = file(name)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              (try? saved.pack.validate(requestedName: name)) != nil else { return nil }
        values[name] = saved
        return saved
    }
    func cached(name: String) -> RemotePack? {
        guard !suspended else { return nil }
        guard let cached = saved(name: name) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file(name).path)
        return cached.pack
    }
    func pack(name: String, client: WorkerClient) async throws -> RemotePack {
        guard !suspended else { throw CancellationError() }
        if let cached = saved(name: name), Date().timeIntervalSince(cached.date) < 600 { return cached.pack }
        let token = generation
        let pack = try await client.pack(name: name)
        try Task.checkCancellation()
        // A concurrent cache clear must not recreate files after the clear finishes.
        guard !suspended, token == generation else { throw CancellationError() }
        let saved = Saved(pack: pack, date: Date())
        values[name] = saved
        if values.count > 200 { values = [name: saved] }
        let data = try JSONEncoder().encode(saved)
        if data.count <= 2 * 1024 * 1024 {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: file(name), options: .atomic)
        }
        return pack
    }
    func beginMaintenance() { generation += 1; suspended = true; values.removeAll() }
    func endMaintenance() { suspended = false }
    func clear() { generation += 1; values.removeAll() }
}
