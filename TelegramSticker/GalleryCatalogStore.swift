import Foundation
import Observation
import CryptoKit

nonisolated struct RemoteGallery: Codable, Sendable {
    struct Pack: Codable, Sendable { let name: String; let link: String }
    let schemaVersion: Int
    let revision: String
    let packs: [Pack]
    func validate() throws {
        let hash = SHA256.hash(data: Data(packs.map(\.name).joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        guard schemaVersion == 1, packs.count <= 200, revision == hash,
              Set(packs.map(\.name)).count == packs.count,
              packs.allSatisfy({ StickerLink.validName($0.name) && $0.name == $0.name.lowercased() &&
                  $0.link == "https://t.me/addstickers/" + $0.name }) else { throw StickerImportError.invalidResponse }
    }
}

@MainActor @Observable
final class GalleryCatalogStore {
    static let shared = GalleryCatalogStore()
    private(set) var packs = GalleryCatalog.packs
    private(set) var notice: String?
    private(set) var refreshing = false
    private var lastAttempt = Date.distantPast
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gallery/catalog-v1.json")
    }
    private init() {
        if let data = try? Data(contentsOf: Self.file), data.count <= 65536,
           let catalog = try? JSONDecoder().decode(RemoteGallery.self, from: data),
           (try? catalog.validate()) != nil { apply(catalog) }
    }
    private func apply(_ catalog: RemoteGallery) {
        packs = catalog.packs.map { GalleryRecommendation(id: $0.name, title: $0.name, symbol: "face.smiling") }
    }
    func refresh(client: WorkerClient, force: Bool = false) async {
        guard !refreshing, force || Date().timeIntervalSince(lastAttempt) >= 60 else { return }
        refreshing = true; lastAttempt = Date()
        defer { refreshing = false }
        do {
            let catalog = try await client.gallery()
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(catalog).write(to: Self.file, options: .atomic)
            apply(catalog); notice = nil
        } catch is CancellationError { lastAttempt = .distantPast }
        catch {
            notice = "추천 목록을 갱신하지 못했어요. 저장된 목록을 표시해요."
            DownloadDiagnostics.shared.record("GALLERY_CATALOG " + DownloadDiagnostics.errorDetails(error))
        }
    }
    func reset() { packs = GalleryCatalog.packs; notice = nil; lastAttempt = .distantPast }
}

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
