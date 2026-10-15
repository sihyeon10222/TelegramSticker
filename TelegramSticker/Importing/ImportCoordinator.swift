import Foundation
import CryptoKit

nonisolated struct BatchImportDraft: Codable, Sendable {
    let origin: URL
    let links: [String]
    var updating = false
}
nonisolated struct ImportDraft: Codable, Sendable {
    let origin: URL
    let link: String
    let pack: RemotePack
}
nonisolated struct DownloadOutcome: Sendable {
    let sticker: RemoteSticker
    let file: URL?
    var animation: URL? = nil
    let bytes: Int
    var failure: ImportFailure? = nil
    var quality: String? = nil
}
nonisolated struct ImportResult: Sendable {
    let installed: Int
    let total: Int
    let failed: Int
    var message: String {
        failed == 0 ? "\(installed)개를 설치했어요. 키보드에서 팩을 선택해 보세요." :
            "\(total)개 중 \(installed)개를 설치했어요. 실패한 \(failed)개는 다시 시도할 수 있어요."
    }
}

actor ImportCoordinator {
    private let writer: LibraryWriter
    private let converter = StaticImageConverter()
    private static let conversionGate = RequestGate(limit: 1)
    private static let pipelineGate = RequestGate(limit: 8)
    private let root: URL
    init(writer: LibraryWriter, root: URL? = nil) {
        self.writer = writer
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportJobs", isDirectory: true)
    }
    func saveBatch(_ draft: BatchImportDraft) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("batch-draft.json")
        if draft.links.isEmpty { try? FileManager.default.removeItem(at: file); return }
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 256 * 1024 else { throw ImportLimitFailure(check: "batch_draft_bytes", actual: String(data.count), limit: "262144 bytes") }
        try data.write(to: file, options: .atomic)
    }
    func batchDraft(for origin: URL) throws -> BatchImportDraft? {
        let file = root.appendingPathComponent("batch-draft.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 256 * 1024 + 1) ?? Data()
        guard data.count <= 256 * 1024 else { return nil }
        let draft = try JSONDecoder().decode(BatchImportDraft.self, from: data)
        return draft.origin == origin ? draft : nil
    }

    func saveDraft(_ draft: ImportDraft) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: root.appendingPathComponent("draft.json"), options: .atomic)
    }
    func draft(for origin: URL) throws -> ImportDraft? {
        let path = root.appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 2 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 2 * 1024 * 1024 else { return nil }
        let draft = try JSONDecoder().decode(ImportDraft.self, from: data)
        guard draft.origin == origin else { return nil }
        try draft.pack.validate(requestedName: StickerLink.parse(draft.link))
        return draft
    }
    func installedResult(for pack: RemotePack) async throws -> ImportResult? {
        guard let installed = try await writer.pack(id: "telegram-" + pack.name) else { return nil }
        return ImportResult(installed: installed.stickers.count, total: installed.originalCount,
                            failed: installed.pendingStickerIDs?.count ?? 0)
    }

    /// One lease protects the batch from cache clearing and other imports. Each
    /// pack gets its own child cache so its cleanup cannot delete a sibling's files.
    func beginBatch(links: [String], origin: URL, updating: Bool) async throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(BatchImportDraft(origin: origin, links: links, updating: updating))
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try await ImportJobCache.shared.begin(root: root, key: key)
    }

    func batchWorker(directory: URL, name: String) throws -> ImportCoordinator {
        guard StickerLink.validName(name) else { throw StickerImportError.invalidLink }
        return ImportCoordinator(writer: writer, root: directory.appendingPathComponent(name, isDirectory: true))
    }

    func orderBatch(links: [String]) async throws {
        let ids = links.compactMap { try? StickerLink.parse($0) }.map { "telegram-" + $0 }
        try await writer.orderImported(ids: ids)
    }

    func endBatch(directory: URL, completed: Bool) async {
        if completed { try? FileManager.default.removeItem(at: directory) }
        await ImportJobCache.shared.end(root: root)
    }

    @discardableResult
    func install(_ pack: RemotePack, client: WorkerClient,
                 updating: Bool = false, onlyIDs: Set<String>? = nil, restoringOriginal: Bool = false,
                 progress: @escaping @Sendable (ImportProgress) async -> Void) async throws -> ImportResult {
        try pack.validate(requestedName: pack.name)
        let existing = try await writer.pack(id: "telegram-" + pack.name)
        if updating, existing == nil { throw LibraryError.invalidOrder }
        if updating, pack.refreshed != true || pack.fetchedAt == nil { throw StickerImportError.refreshUnsupported }
        if let existing, !updating, existing.pendingStickerIDs?.isEmpty != false { throw LibraryError.duplicatePack }
        guard pack.stickerType == "regular", updating || !pack.installableStickers.isEmpty else { throw StickerImportError.noStaticStickers }
        let oldByID = Dictionary(uniqueKeysWithValues: (existing?.stickers ?? []).map { ($0.id, $0) })
        let reusable: Set<String>
        if updating, !restoringOriginal, let existing { reusable = try await writer.reusableStickerIDs(in: existing) } else { reusable = [] }
        let requestedIDs = updating ? pack.installableStickers.filter { oldByID[$0.id]?.sourceFormat != $0.format || !reusable.contains($0.id) }.map(\.id)
            : existing?.pendingStickerIDs ?? pack.installableStickers.map(\.id)
        let requested = Set(requestedIDs)
        let candidates = pack.installableStickers.filter { requested.contains($0.id) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var cachePack = pack; cachePack.fetchedAt = nil; cachePack.refreshed = nil
        var signature = try encoder.encode(cachePack)
        if restoringOriginal { signature.append(contentsOf: "restore-original-v1".utf8) }
        signature.append(contentsOf: client.configuration.origin.absoluteString.utf8)
        if candidates.contains(where: { $0.format != "static" }) {
            // Do not reuse GIFs produced before timing correction/frame sampling changes.
            signature.append(contentsOf: "animation-pipeline-v3-file".utf8)
        }
        let key = SHA256.hash(data: signature).map { String(format: "%02x", $0) }.joined()
        let directory = try await ImportJobCache.shared.begin(root: root, key: key)
        let eligible = candidates.filter { onlyIDs == nil || onlyIDs!.contains($0.id) || FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.id + ".png").path) }
        do {
            let result = try await downloadAndPublish(pack, existing: existing, requestedIDs: requestedIDs,
                candidates: eligible, client: client, directory: directory, updating: updating, progress: progress)
            await ImportJobCache.shared.end(root: root)
            return result
        } catch {
            await ImportJobCache.shared.end(root: root)
            throw error
        }
    }

    private func downloadAndPublish(_ pack: RemotePack, existing: PackManifestV1?, requestedIDs: [String],
                                    candidates: [RemoteSticker], client: WorkerClient,
                                    directory: URL, updating: Bool,
                                    progress: @escaping @Sendable (ImportProgress) async -> Void) async throws -> ImportResult {
        let converter = self.converter
        var finished: [String: DownloadOutcome] = [:]
        let previousCount = existing?.stickers.count ?? 0
        let total = updating ? pack.stickers.count : existing?.originalCount ?? pack.stickers.count
        // Updated items replace old items; counting the whole old pack and then
        // adding new downloads would reach 100% before those downloads finish.
        let readyCount = updating ? max(0, total - requestedIDs.count) : previousCount
        var failures = await ImportFailureStore.shared.load(name: pack.name)
        failures.removeAll { !requestedIDs.contains($0.id) }
        for id in requestedIDs where !pack.stickers.contains(where: { $0.id == id }) && !failures.contains(where: { $0.id == id }) {
            failures.append(ImportFailure(id: id, format: "unknown", stage: "조회", code: "asset_unavailable", message: "원본 팩에서 항목을 찾을 수 없어요. 팩 업데이트 확인로 목록을 다시 맞출 수 있어요.", retryable: false))
        }
        let candidateIDs = Set(candidates.map(\.id))
        failures.removeAll { candidateIDs.contains($0.id) }
        var failed = requestedIDs.count - candidates.count
        await progress(ImportProgress(completed: readyCount, total: total, failed: failed))
        try await withThrowingTaskGroup(of: DownloadOutcome.self) { group in
            func add(_ sticker: RemoteSticker) {
                group.addTask {
                    return try await DiagnosticContext.$packName.withValue(pack.name) {
                        try await Self.pipelineGate.acquire()
                        defer { Task { await Self.pipelineGate.release() } }
                        try Task.checkCancellation()
                        let output = directory.appendingPathComponent(sticker.id + ".png")
                        let animation = directory.appendingPathComponent(sticker.id + ".gif")
                        let animated = sticker.format != "static"
                        // Initial download plus at most five complete re-downloads.
                        for retryAttempt in 0...5 {
                            try await BackgroundWork.shared.waitForExecution()
                            var stage = "다운로드"
                            let attemptStarted = ContinuousClock.now
                            var receivedBytes: Int?
                            var fileMagic = "unknown"
                            do {
                                if FileManager.default.fileExists(atPath: output.path),
                                   let data = try? Data(contentsOf: output, options: .mappedIfSafe), PNGValidation.isValid(data) {
                                    if !animated { return DownloadOutcome(sticker: sticker, file: output, bytes: data.count) }
                                    if let size = try? animation.resourceValues(forKeys: [.fileSizeKey]).fileSize, GIFValidation.isValid(url: animation) {
                                        return DownloadOutcome(sticker: sticker, file: output, animation: animation, bytes: data.count + size, quality: (try? String(contentsOf: directory.appendingPathComponent(sticker.id + ".quality"), encoding: .utf8)))
                                    }
                                }
                                let source = directory.appendingPathComponent(sticker.id + ".source")
                                defer { try? FileManager.default.removeItem(at: source) }
                                _ = try await client.assetFile(pack: pack.name, sticker: sticker, destination: source)
                                // Download the next files while one animation is being converted.
                                try await Self.conversionGate.acquire()
                                defer { Task { await Self.conversionGate.release() } }
                                try Task.checkCancellation()
                                try await BackgroundWork.shared.waitForExecution()
                                let original = try Data(contentsOf: source, options: .mappedIfSafe)
                                receivedBytes = original.count
                                fileMagic = original.prefix(16).map { String(format: "%02x", $0) }.joined()
                                await DownloadDiagnostics.shared.record("PIPELINE pack=\(pack.name) stickerID=\(sticker.id) format=\(sticker.format) dimensions=\(sticker.width)x\(sticker.height) declaredBytes=\(sticker.fileSize.map(String.init) ?? "unknown") receivedBytes=\(original.count) magic16=\(fileMagic) attempt=\(retryAttempt + 1)/6 stage=convert")
                                try Task.checkCancellation()
                                stage = "변환"
                                let png: Data
                                var qualityLabel: String?
                                if animated {
                                    var converted: ConvertedAnimation?
                                    for (index, quality) in AnimationQuality.fallback.enumerated() {
                                        do {
                                            if sticker.format == "animated" { converted = try await TGSConverter.convert(original, output: animation, quality: quality) }
                                            else { converted = try await WebMConverter().convert(original, output: animation, quality: quality) }
                                            if index > 0 { qualityLabel = quality.label }
                                            break
                                        } catch {
                                            await DownloadDiagnostics.shared.record("CONVERSION pack=\(pack.name) stickerID=\(sticker.id) quality=\(quality.label) " + DownloadDiagnostics.errorDetails(error))
                                            let resourceFailure = isConversionTimeout(error) ||
                                                [WebMConversionFailure.deadline, .image, .output].contains(error as? WebMConversionFailure ?? .bitstream)
                                            guard resourceFailure, index < AnimationQuality.fallback.count - 1 else { throw error }
                                        }
                                    }
                                    guard let converted else { throw StickerImportError.unsupportedFormat }
                                    png = converted.poster
                                    qualityLabel = converted.quality ?? qualityLabel
                                } else { png = try await converter.png(from: original) }
                                try Task.checkCancellation()
                                stage = "저장"
                                try png.write(to: output, options: .atomic)
                                if let qualityLabel { try qualityLabel.write(to: directory.appendingPathComponent(sticker.id + ".quality"), atomically: true, encoding: .utf8) }
                                return DownloadOutcome(sticker: sticker, file: output, animation: animated ? animation : nil,
                                    bytes: png.count, quality: qualityLabel)
                            } catch is CancellationError { throw CancellationError() }
                            catch {
                                if Task.isCancelled { throw CancellationError() }
                                let failure = ImportFailure.record(sticker: sticker, stage: stage, error: error)
                                let stopForLimit = error is ImportLimitFailure
                                let action = stopForLimit ? "확정된 제한 초과 · 자동 반복 중지" : retryAttempt < 5 ? "자동 재다운로드 \(retryAttempt + 1)/5" : "5회 재시도 종료"
                                await DownloadDiagnostics.shared.record("FAIL pack=\(pack.name) code=\(failure.code) attempt=\(retryAttempt + 1)/6 elapsed=\(attemptStarted.duration(to: .now)) receivedBytes=\(receivedBytes.map(String.init) ?? "unknown") magic16=\(fileMagic) action=\(action) " + (failure.technicalDetails ?? failure.message))
                                if retryAttempt == 5 || stopForLimit { return DownloadOutcome(sticker: sticker, file: nil, bytes: 0, failure: failure) }
                                var seconds = min(30.0, pow(2.0, Double(retryAttempt + 1)))
                                if case let StickerImportError.server(_, _, retryAfter) = error { seconds = max(seconds, Double(retryAfter)) }
                                try await Task.sleep(for: .seconds(seconds + Double.random(in: 0.2...1.5)))
                            }
                        }
                        throw StickerImportError.network
                    }
                }
            }
            // Downloads have no app-imposed concurrency cap. Expensive frame
            // rendering remains serialized independently of network transfers.
            for sticker in candidates { add(sticker) }
            while let result = try await group.next() {
                try Task.checkCancellation()
                if let existing, try await !writer.hasRevision(id: existing.id, revision: existing.revision) {
                    group.cancelAll(); throw LibraryError.invalidOrder
                }
                if result.file != nil { finished[result.sticker.id] = result } else { failed += 1 }
                if let failure = result.failure { failures.append(failure) }
                try await ImportFailureStore.shared.save(name: pack.name, failures: failures)
                await progress(ImportProgress(completed: readyCount + finished.count, total: total, failed: failed))
            }
        }
        guard updating || previousCount + finished.count > 0 else { throw StickerImportError.partial(completed: 0, total: total) }
        try Task.checkCancellation()
        let pending = requestedIDs.filter { finished[$0] == nil }
        try await ImportFailureStore.shared.save(name: pack.name, failures: failures)
        if updating, !pending.isEmpty { throw StickerImportError.updateFailed }
        if updating || !finished.isEmpty {
            let oldInputs: [LocalStickerInput]
            if let existing { oldInputs = try await writer.inputs(for: existing) }
            else { oldInputs = [] }
            var available = Dictionary(uniqueKeysWithValues: oldInputs.map { ($0.id, $0) })
            for (index, sticker) in pack.stickers.enumerated() {
                if let result = finished[sticker.id], let file = result.file {
                    available[sticker.id] = LocalStickerInput(id: sticker.id, name: sticker.emoji ?? "스티커 \(index + 1)",
                        url: file, sourceFormat: sticker.format, animationURL: result.animation, conversionQuality: result.quality)
                }
            }
            // Keep the source order, preserving installed items removed from the remote pack.
            let ordered = pack.stickers.compactMap { available.removeValue(forKey: $0.id) }
            let retained = updating ? [] : oldInputs.filter { available[$0.id] != nil }
            try await writer.install(id: "telegram-" + pack.name, title: pack.title, stickers: ordered + retained,
                originalCount: total, telegramName: pack.name, pendingStickerIDs: pending, replacingRevision: existing?.revision, mirroringRemote: updating,
                lastCheckedAt: updating ? pack.fetchedAt.map { Date(timeIntervalSince1970: $0) } : existing?.lastCheckedAt)
        } else if let existing {
            guard try await writer.pack(id: existing.id)?.revision == existing.revision else { throw LibraryError.invalidOrder }
        }
        if pending.isEmpty { try? FileManager.default.removeItem(at: directory) }
        if pending.isEmpty { try? FileManager.default.removeItem(at: root.appendingPathComponent("draft.json")) }
        await progress(ImportProgress(completed: updating ? pack.stickers.count : previousCount + finished.count,
                                      total: total, failed: pending.count, applied: pending.isEmpty))
        return ImportResult(installed: updating ? pack.stickers.count : previousCount + finished.count, total: total, failed: pending.count)
    }
}

nonisolated private func isConversionTimeout(_ error: Error) -> Bool {
    if case StickerImportError.conversionTimeout = error { return true }; return false
}
