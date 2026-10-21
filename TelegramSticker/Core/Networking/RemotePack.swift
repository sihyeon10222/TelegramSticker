import Foundation

nonisolated struct RemotePack: Codable, Sendable, Equatable {
    let name: String
    let title: String
    let stickerType: String
    let stickers: [RemoteSticker]
    var fetchedAt: Double? = nil
    var refreshed: Bool? = nil
    var installableStickers: [RemoteSticker] { stickerType == "regular" ? stickers : [] }
    func validate(requestedName: String) throws {
        guard fetchedAt == nil || (fetchedAt!.isFinite && fetchedAt! > 0),
              StickerLink.validName(name), name == requestedName, title.count <= 256, !title.isEmpty,
              ["regular", "mask", "custom_emoji"].contains(stickerType), stickers.count <= 1000,
              Set(stickers.map(\.id)).count == stickers.count,
              stickers.allSatisfy({ $0.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil &&
                  ["static", "animated", "video"].contains($0.format) && (1...4096).contains($0.width) &&
                  (1...4096).contains($0.height) && ($0.fileSize ?? 0) >= 0 }) else { throw StickerImportError.invalidResponse }
    }
}
nonisolated struct RemoteSticker: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let format: String
    let width: Int
    let height: Int
    let emoji: String?
    let fileSize: Int?
    let hasThumbnail: Bool
}
