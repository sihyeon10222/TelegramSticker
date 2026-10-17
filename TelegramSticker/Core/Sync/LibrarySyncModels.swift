import Foundation
import CloudKit

nonisolated struct LibrarySyncVersion: Codable, Equatable, Sendable, Comparable {
    let counter: Int64
    let deviceID: String
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.deviceID < rhs.deviceID : lhs.counter < rhs.counter
    }
}
nonisolated struct SyncedPack: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let telegramName: String
    let title: String
    var deleted: Bool
    var version: LibrarySyncVersion

    func supersedes(_ old: Self) -> Bool {
        if version.counter == old.version.counter, deleted != old.deleted { return deleted }
        return version > old.version
    }
    var isValid: Bool {
        StickerLink.validName(telegramName) && telegramName == telegramName.lowercased()
            && id == "telegram-" + telegramName && title.count <= 256
            && version.counter >= 0 && version.counter < Int64.max - 1 && version.deviceID.count <= 100
    }
}
nonisolated struct SyncedPackOrder: Codable, Equatable, Sendable {
    var ids: [String]
    var version: LibrarySyncVersion
}

/// Kept separately from the installed-library schema; the keyboard never reads this file.
nonisolated struct LibrarySyncStore: Codable, Sendable {
    var schemaVersion = 1
    var clock: Int64 = 0
    var bootstrapped = false
    var packs: [String: SyncedPack] = [:]
    var order: SyncedPackOrder?
    var pending = Set<String>()
    var appliedEvents = Set<String>()
    var systemFields: [String: Data] = [:]
    var engineState: CKSyncEngine.State.Serialization?
    var lastCompleted: Date?

    var orderedPacks: [SyncedPack] {
        let active = packs.filter { !$0.value.deleted }
        var seen = Set<String>()
        let ids = ((order?.ids ?? []) + active.keys.sorted()).filter { active[$0] != nil && seen.insert($0).inserted }
        return ids.compactMap { active[$0] }
    }
    static func url(account: String) -> URL {
        LibraryChangeJournal.root.appendingPathComponent(account + ".json")
    }
    static func load(account: String) throws -> Self {
        let url = url(account: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let data = try Data(contentsOf: url)
        guard data.count <= 16 * 1024 * 1024 else { throw LibraryError.invalidIndex }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, value.clock >= 0, value.clock < Int64.max - 1,
              value.packs.allSatisfy({ $0.key == $0.value.id && $0.value.isValid }) else { throw LibraryError.invalidIndex }
        return value
    }
    func save(account: String) throws {
        try FileManager.default.createDirectory(at: LibraryChangeJournal.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url(account: account), options: .atomic)
    }
}
