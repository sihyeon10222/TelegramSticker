import Foundation

/// Write-ahead journal owned by LibraryWriter. Only committed index changes reach CloudKit.
nonisolated struct LibraryChange: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case install, delete, order }
    var id = UUID().uuidString
    var createdAt = Date()
    let kind: Kind
    var packID: String?
    var telegramName: String?
    var title: String?
    var orderedIDs: [String]?
    var version: LibrarySyncVersion?
    var targetRevision: String = ""
}

nonisolated enum LibraryChangeJournal {
    private static let clockLock = NSLock()
    static let notification = Notification.Name("StickerBridgeLibraryCommitted")
    static let enabledKey = "librarySyncEnabled"
    static let accountKey = "librarySyncAccount"
    static var cloudKitConfigured: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "StickerBridgeCloudKitEnabled")
        return (value as? Bool) == true || (value as? String)?.uppercased() == "YES"
    }
    static var enabled: Bool {
        cloudKitConfigured && UserDefaults.standard.object(forKey: enabledKey) as? Bool != false
    }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibrarySync", isDirectory: true)
    }
    static var directory: URL { root.appendingPathComponent("Journal", isDirectory: true) }
    static var scope: String { UserDefaults.standard.string(forKey: accountKey) ?? "unassigned" }

    static func prepare(_ change: LibraryChange, directory: URL) throws -> URL {
        var change = change
        let accountScope = scope
        change.version = try nextVersion(scope: accountScope)
        let folder = directory.appendingPathComponent(accountScope, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(change.id + ".pending")
        try JSONEncoder().encode(change).write(to: url, options: .atomic)
        return url
    }
    static func observe(counter: Int64) throws {
        clockLock.lock(); defer { clockLock.unlock() }
        let url = root.appendingPathComponent("clock-" + scope + ".json")
        let previous = FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode(Int64.self, from: Data(contentsOf: url)) : 0
        if counter > previous {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(counter).write(to: url, options: .atomic)
        }
    }
    static func nextVersion(scope: String = scope) throws -> LibrarySyncVersion {
        clockLock.lock(); defer { clockLock.unlock() }
        let url = root.appendingPathComponent("clock-" + scope + ".json")
        let previous = FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode(Int64.self, from: Data(contentsOf: url)) : 0
        guard previous < Int64.max - 1 else { throw LibraryError.invalidIndex }
        let device = UserDefaults.standard.string(forKey: "librarySyncDeviceID") ?? UUID().uuidString
        UserDefaults.standard.set(device, forKey: "librarySyncDeviceID")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(previous + 1).write(to: url, options: .atomic)
        return LibrarySyncVersion(counter: previous + 1, deviceID: device)
    }
    static func commit(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("json"))
        NotificationCenter.default.post(name: notification, object: nil)
    }
    static func recover(directory: URL, revision: String) throws {
        let fm = FileManager.default
        for folder in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "pending" {
                let change = try JSONDecoder().decode(LibraryChange.self, from: Data(contentsOf: url))
                if change.targetRevision == revision { commit(url) }
                else { try fm.removeItem(at: url) }
            }
        }
    }
    static func changes(account: String, includeUnassigned: Bool) throws -> [(URL, LibraryChange)] {
        var result: [(URL, LibraryChange)] = []
        for scope in [account] + (includeUnassigned ? ["unassigned"] : []) {
            let folder = directory.appendingPathComponent(scope)
            for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
                let data = try Data(contentsOf: url)
                guard data.count <= 256 * 1024 else { throw LibraryError.invalidIndex }
                result.append((url, try JSONDecoder().decode(LibraryChange.self, from: data)))
            }
        }
        return result.sorted { ($0.1.createdAt, $0.1.id) < ($1.1.createdAt, $1.1.id) }
    }
}
