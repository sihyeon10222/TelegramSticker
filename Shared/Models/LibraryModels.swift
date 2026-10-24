import Foundation

nonisolated enum LibraryError: Error, LocalizedError {
    case unavailable, invalidIndex, unsupportedVersion, unsafePath, duplicatePack, invalidImage, invalidOrder
    var errorDescription: String? {
        switch self {
        case .unavailable: "공유 저장소에 접근할 수 없어요. 앱과 키보드의 App Group 서명을 확인해 주세요."
        case .invalidIndex: "스티커 목록을 읽을 수 없어요. 기존 파일은 보존했어요."
        case .unsupportedVersion: "더 새로운 스티커 저장소 형식이에요. 최신 버전의 앱을 설치해 주세요."
        case .unsafePath: "안전하지 않은 파일 경로를 차단했어요."
        case .duplicatePack: "이미 설치한 팩이에요."
        case .invalidImage: "손상되었거나 지원하지 않는 PNG·GIF예요."
        case .invalidOrder: "팩 목록이 바뀌었어요. 새로고침 후 다시 시도해 주세요."
        }
    }
}

nonisolated struct LibraryIndexV1: Codable, Sendable {
    var schemaVersion = 1
    var libraryRevision = UUID().uuidString
    var packs: [PackReference] = []
    var cacheGeneration: String? = nil
}
nonisolated struct PackReference: Codable, Sendable, Identifiable {
    let id: String
    let manifestPath: String
}
nonisolated struct PackManifestV1: Codable, Sendable, Identifiable {
    var schemaVersion = 1
    let id: String
    let title: String
    let revision: String
    let originalCount: Int
    let stickers: [StickerRecord]
    var telegramName: String? = nil
    var pendingStickerIDs: [String]? = nil
    var lastCheckedAt: Date? = nil
}
nonisolated struct StickerRecord: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let format: String
    let pngPath: String
    let thumbnailPath: String
    let sha256: String
    var sourceFormat: String? = nil
    var animationPath: String? = nil
    var playbackPath: String? = nil
    var conversionQuality: String? = nil
}
nonisolated struct LibrarySnapshot: Sendable {
    let revision: String
    let packs: [PackManifestV1]
    let warnings: [String]
    var cacheGeneration: String? = nil
    var files: [String: URL] = [:]
    var references: [PackReference] = []
}

/// Validated manifest metadata. Asset paths are resolved by Sticker on access.
nonisolated struct LibraryContents: Sendable {
    let reader: LibraryReader
    let snapshot: LibrarySnapshot
    let stickers: [String: [Sticker]]
    let byStickerID: [String: Sticker]
    let stickerIDs: Set<String>
    let covers: [String: Sticker]

    init(reader: LibraryReader, snapshot: LibrarySnapshot) {
        self.reader = reader
        self.snapshot = snapshot
        var stickers: [String: [Sticker]] = [:]
        var byID: [String: Sticker] = [:]
        var covers: [String: Sticker] = [:]
        for pack in snapshot.packs {
            let items = pack.stickers.map { record in
                Sticker(id: pack.id + "." + record.id, name: record.name, detail: pack.title,
                    reader: reader, imagePath: record.pngPath, thumbnailPath: record.thumbnailPath,
                    animationPath: record.animationPath, playbackPath: record.playbackPath)
            }
            stickers[pack.id] = items
            for item in items { byID[item.id] = item }
            if let first = pack.stickers.first {
                covers[pack.id] = Sticker(id: pack.id + "." + pack.revision, name: pack.title, detail: "",
                    reader: reader, thumbnailPath: first.thumbnailPath,
                    animationPath: first.playbackPath ?? first.animationPath)
            }
        }
        self.stickers = stickers
        byStickerID = byID
        stickerIDs = Set(byID.keys)
        self.covers = covers
    }
}
