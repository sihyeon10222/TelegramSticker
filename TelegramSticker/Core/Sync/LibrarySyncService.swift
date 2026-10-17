import Foundation
import CloudKit
import CryptoKit
import Observation

/// Cloud metadata only. Downloads and presentation are connected by the app layer.
@MainActor @Observable
final class LibrarySyncService: CKSyncEngineDelegate {
    static let shared = LibrarySyncService()
    static let containerIdentifier = "iCloud.com.sihyeon.TelegramSticker"
    private static let zoneID = CKRecordZone.ID(zoneName: "StickerLibrary")
    var enabled = UserDefaults.standard.object(forKey: LibraryChangeJournal.enabledKey) as? Bool != false
    private(set) var status = LibraryChangeJournal.cloudKitConfigured ? "iCloud 연결 대기 중" : "iCloud 사용에는 Apple Developer 팀 설정이 필요해요."
    private(set) var isSyncing = false
    private(set) var changeID = 0
    private(set) var lastCompleted: Date?
    private(set) var accountConfirmationRequired = false
    private(set) var desiredPacks: [SyncedPack] = []
    private(set) var deletedPackIDs = Set<String>()
    private var store = LibrarySyncStore()
    private var account: String?
    private var awaitingAccount: String?
    private var engine: CKSyncEngine?
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var fetchedError: String?
    private var container: CKContainer { CKContainer(identifier: Self.containerIdentifier) }

    private init() {
        let defaults = UserDefaults.standard
        let deviceID = defaults.string(forKey: "librarySyncDeviceID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "librarySyncDeviceID")
    }

    func synchronize() async {
        guard enabled, LibraryChangeJournal.cloudKitConfigured else { return }
        if let operation { await operation.value; return }
        let currentGeneration = generation
        let task = Task { await self.performSync(generation: currentGeneration) }
        operation = task
        await task.value
        if currentGeneration == generation { operation = nil }
    }

    private func performSync(generation expected: Int) async {
        isSyncing = true
        defer { if generation == expected { isSyncing = false } }
        do {
            guard try await connect(generation: expected), let engine, let account else { return }
            try ensureCurrent(expected)
            if store.bootstrapped { try await drainJournal() }
            status = "iCloud 변경 확인 중"
            fetchedError = nil
            try await engine.fetchChanges()
            try ensureCurrent(expected)
            if let fetchedError { throw SyncError.message(fetchedError) }
            guard let writer = LibraryWriter.shared else { throw LibraryError.unavailable }
            try await writer.recoverChangeJournal()
            let events = try LibraryChangeJournal.changes(account: account, includeUnassigned: true)
            do {
                let snapshot = try await Task.detached { try LibraryReader.shared().snapshot(resolvingFiles: false) }.value
                try ensureCurrent(expected)
                for pack in snapshot.packs where store.packs[pack.id] == nil {
                    guard let name = pack.telegramName, StickerLink.validName(name) else { continue }
                    store.packs[pack.id] = SyncedPack(id: pack.id, telegramName: name, title: pack.title, deleted: false,
                        version: try nextVersion())
                    store.pending.insert(pack.id)
                }
                let cloudOrder = store.order?.ids ?? []
                var seen = Set(cloudOrder)
                let combined = cloudOrder + snapshot.packs.map(\.id).filter { seen.insert($0).inserted }
                if store.order == nil || combined != cloudOrder {
                    store.order = SyncedPackOrder(ids: combined, version: try nextVersion())
                    store.pending.insert("order")
                }
                store.bootstrapped = true
            }
            for (_, change) in events where !store.appliedEvents.contains(change.id) {
                try apply(change)
                store.appliedEvents.insert(change.id)
            }
            // Persist merged data and event acknowledgements before removing journal entries.
            try persist()
            for (url, change) in events where store.appliedEvents.contains(change.id) { try? FileManager.default.removeItem(at: url) }
            publishDesired()
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            queuePending(on: engine)
            status = "iCloud 변경 전송 중"
            try await engine.sendChanges()
            try ensureCurrent(expected)
            guard store.pending.isEmpty else {
                status = "일부 변경 전송 대기 중 · 지금 동기화로 다시 시도할 수 있어요."
                return
            }
            store.lastCompleted = Date(); lastCompleted = store.lastCompleted
            try persist()
            status = "최신 상태"
        } catch is CancellationError { }
        catch {
            if generation == expected { status = "동기화 대기 · " + error.localizedDescription }
        }
    }

    private func connect(generation expected: Int) async throws -> Bool {
        let availability = try await container.accountStatus()
        try Task.checkCancellation()
        guard enabled, generation == expected else { throw CancellationError() }
        guard availability == .available else {
            await disconnect()
            status = "iCloud에 로그인하면 동기화를 계속해요. 로컬 팩은 유지됩니다."
            return false
        }
        let user = try await container.userRecordID()
        try Task.checkCancellation()
        guard enabled, generation == expected else { throw CancellationError() }
        let key = SHA256.hash(data: Data(user.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
        if let previous = UserDefaults.standard.string(forKey: LibraryChangeJournal.accountKey), previous != key {
            awaitingAccount = key; accountConfirmationRequired = true
            await disconnect()
            status = "Apple 계정이 바뀌었어요. 새 계정 연결을 확인해 주세요."
            return false
        }
        if account == key, engine != nil { return true }
        store = try LibrarySyncStore.load(account: key)
        account = key
        UserDefaults.standard.set(key, forKey: LibraryChangeJournal.accountKey)
        try LibraryChangeJournal.observe(counter: store.clock)
        lastCompleted = store.lastCompleted
        var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
            stateSerialization: store.engineState, delegate: self)
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
        return true
    }

    private func ensureCurrent(_ expected: Int) throws {
        try Task.checkCancellation()
        guard generation == expected, enabled, account != nil else { throw CancellationError() }
    }

    func confirmNewAccount() async {
        guard let awaitingAccount else { return }
        await disconnect()
        UserDefaults.standard.set(awaitingAccount, forKey: LibraryChangeJournal.accountKey)
        self.awaitingAccount = nil; accountConfirmationRequired = false
        generation += 1
        operation?.cancel(); operation = nil
        await synchronize()
    }

    func setEnabled(_ value: Bool) async {
        enabled = value
        UserDefaults.standard.set(value, forKey: LibraryChangeJournal.enabledKey)
        generation += 1
        operation?.cancel(); operation = nil; isSyncing = false
        if value { await synchronize() }
        else { await disconnect(); status = "이 기기의 동기화가 꺼져 있어요. 클라우드 팩은 유지됩니다." }
    }

    /// Called before local reset. No cloud delete or old-account replay is generated.
    func stopForReset() async {
        await setEnabled(false)
        let folders = [LibraryChangeJournal.scope, "unassigned"]
        for folder in folders {
            try? FileManager.default.removeItem(at: LibraryChangeJournal.directory.appendingPathComponent(folder))
        }
    }

    private func disconnect() async {
        let old = engine
        engine = nil; account = nil
        desiredPacks = []; deletedPackIDs = []; changeID += 1
        await old?.cancelOperations()
    }

    private func nextVersion() throws -> LibrarySyncVersion {
        try LibraryChangeJournal.observe(counter: store.clock)
        let version = try LibraryChangeJournal.nextVersion()
        store.clock = version.counter
        return version
    }
    private func apply(_ change: LibraryChange) throws {
        let version = try change.version ?? nextVersion()
        store.clock = max(store.clock, version.counter)
        switch change.kind {
        case .install:
            guard let id = change.packID, let name = change.telegramName, StickerLink.validName(name), id == "telegram-" + name else { return }
            let value = SyncedPack(id: id, telegramName: name, title: change.title ?? name, deleted: false, version: version)
            if let old = store.packs[id], !value.supersedes(old) { return }
            store.packs[id] = value
            store.pending.insert(id)
        case .delete:
            guard let id = change.packID, id.hasPrefix("telegram-") else { return }
            let name = String(id.dropFirst("telegram-".count))
            guard StickerLink.validName(name) else { return }
            let value = SyncedPack(id: id, telegramName: name, title: store.packs[id]?.title ?? name, deleted: true, version: version)
            if let old = store.packs[id], !value.supersedes(old) { return }
            store.packs[id] = value
            store.pending.insert(id)
        case .order:
            guard let ids = change.orderedIDs, ids.count <= 1000 else { return }
            if let order = store.order, order.version >= version { return }
            store.order = SyncedPackOrder(ids: ids, version: version)
            store.pending.insert("order")
        }
    }

    private func drainJournal() async throws {
        guard let account, let writer = LibraryWriter.shared else { return }
        try await writer.recoverChangeJournal()
        try Task.checkCancellation()
        guard self.account == account else { throw CancellationError() }
        let events = try LibraryChangeJournal.changes(account: account, includeUnassigned: true)
        for (_, change) in events where !store.appliedEvents.contains(change.id) {
            try apply(change); store.appliedEvents.insert(change.id)
        }
        try persist()
        for (url, _) in events { try? FileManager.default.removeItem(at: url) }
    }
    private func queuePending(on engine: CKSyncEngine, names: Set<String>? = nil) {
        let existing = Set(engine.state.pendingRecordZoneChanges)
        let pending = (names ?? store.pending).map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID($0)) }.filter { !existing.contains($0) }
        if !pending.isEmpty { engine.state.add(pendingRecordZoneChanges: pending) }
    }
    private func persist() throws {
        if let account { try store.save(account: account) }
    }
    private func publishDesired() {
        guard store.bootstrapped else { return }
        let desired = store.orderedPacks
        let deleted = Set(store.packs.values.filter(\.deleted).map(\.id))
        if desired != desiredPacks || deleted != deletedPackIDs {
            desiredPacks = desired; deletedPackIDs = deleted; changeID += 1
        }
    }
    private func recordID(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: Self.zoneID) }
    private func record(_ name: String) -> CKRecord? {
        let record: CKRecord
        if let data = store.systemFields[name],
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            guard let restored = CKRecord(coder: coder) else { return nil }
            record = restored; coder.finishDecoding()
        } else { record = CKRecord(recordType: name == "order" ? "PackOrder" : "Pack", recordID: recordID(name)) }
        if name == "order", let order = store.order {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            record["payload"] = try? encoder.encode(order) as NSData
        } else if let pack = store.packs[name] {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            record["payload"] = try? encoder.encode(pack) as NSData
        } else { return nil }
        return record
    }
    private func cacheSystemFields(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding()
        store.systemFields[record.recordID.recordName] = coder.encodedData
    }
    private func merge(_ record: CKRecord) throws {
        guard record.recordID.zoneID == Self.zoneID, let data = record["payload"] as? Data, data.count <= 256 * 1024 else { throw LibraryError.invalidIndex }
        let name = record.recordID.recordName
        cacheSystemFields(record)
        if name == "order" {
            let value = try JSONDecoder().decode(SyncedPackOrder.self, from: data)
            guard value.ids.count <= 1000, Set(value.ids).count == value.ids.count,
                  value.ids.allSatisfy(LibraryReader.safeID), value.version.counter >= 0,
                  value.version.counter < Int64.max - 1, value.version.deviceID.count <= 100 else { throw LibraryError.invalidIndex }
            store.clock = max(store.clock, value.version.counter)
            try LibraryChangeJournal.observe(counter: store.clock)
            if store.order == nil || value.version > store.order!.version { store.order = value; store.pending.remove(name) }
            else if value != store.order { store.pending.insert(name) }
        } else {
            let value = try JSONDecoder().decode(SyncedPack.self, from: data)
            guard value.isValid, value.id == name else { throw LibraryError.invalidIndex }
            store.clock = max(store.clock, value.version.counter)
            try LibraryChangeJournal.observe(counter: store.clock)
            if let old = store.packs[name] {
                if value.supersedes(old) { store.packs[name] = value; store.pending.remove(name) }
                else if old != value { store.pending.insert(name) }
            } else { store.packs[name] = value }
        }
    }

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, engine: syncEngine)
    }
    private func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) async {
        guard engine === self.engine, enabled, account != nil else { return }
        do {
            var resubmit = Set<String>()
            switch event {
            case .stateUpdate(let event): store.engineState = event.stateSerialization
            case .fetchedRecordZoneChanges(let event):
                if store.bootstrapped { try await drainJournal() }
                guard engine === self.engine else { return }
                for modification in event.modifications { try merge(modification.record) }
                resubmit = store.pending
                // Our protocol uses tombstones. Unexpected hard deletions never delete installed files.
                if !event.deletions.isEmpty { status = "클라우드 레코드가 제거되었어요. 로컬 팩을 유지합니다." }
            case .sentRecordZoneChanges(let event):
                for record in event.savedRecords {
                    cacheSystemFields(record)
                    if let payload = record["payload"] as? Data, let current = self.record(record.recordID.recordName)?["payload"] as? Data, payload == current {
                        store.pending.remove(record.recordID.recordName)
                    } else { store.pending.insert(record.recordID.recordName); resubmit.insert(record.recordID.recordName) }
                }
                for failure in event.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                        try merge(server)
                        if store.pending.contains(server.recordID.recordName) { resubmit.insert(server.recordID.recordName) }
                    }
                    else if failure.error.code == .zoneNotFound {
                        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                        store.systemFields.removeValue(forKey: failure.record.recordID.recordName)
                        resubmit.insert(failure.record.recordID.recordName)
                    } else { status = "동기화 대기 · " + failure.error.localizedDescription }
                }
            case .didFetchRecordZoneChanges(let event):
                if let error = event.error, error.code != .zoneNotFound { fetchedError = error.localizedDescription }
            case .accountChange(let event):
                switch event.changeType {
                case .signIn: break
                case .signOut, .switchAccounts:
                    generation += 1; operation?.cancel(); operation = nil; isSyncing = false
                    self.engine = nil; account = nil
                    desiredPacks = []; deletedPackIDs = []; changeID += 1
                    Task { await engine.cancelOperations() }
                    status = "iCloud 계정 변경 · 다시 연결하면 동기화를 계속해요."
                    return
                @unknown default: break
                }
            default: break
            }
            try persist()
            publishDesired()
            if store.bootstrapped && !resubmit.isEmpty {
                queuePending(on: engine, names: resubmit)
            }
        } catch {
            fetchedError = error.localizedDescription
            status = "동기화 저장 확인 필요 · " + error.localizedDescription
        }
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await nextBatch(context, engine: syncEngine)
    }
    private func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === self.engine, enabled, store.bootstrapped, account != nil else { return nil }
        let records = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
            .compactMap { change -> CKRecord.ID? in
                if case .saveRecord(let id) = change, store.pending.contains(id.recordName) { return id }
                return nil
            }.sorted { $0.recordName < $1.recordName }.prefix(100).compactMap { record($0.recordName) }
        return records.isEmpty ? nil : CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records)
    }

    private enum SyncError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
