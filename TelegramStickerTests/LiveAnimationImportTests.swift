import Foundation
import Testing
@testable import TelegramSticker

/// Explicit opt-in only. Uses the containing app's normal Keychain configuration,
/// never prints credentials, writes only a temporary library, and cleans it up.
@MainActor
struct LiveAnimationImportTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STICKERBRIDGE_LIVE_IMPORT"] == "1"))
    func realTelegramTGSAndWebMPacksConvertAndPublish() async throws {
        guard let configuration = try ImportSettings.load() else {
            Issue.record("실기기 앱에서 먼저 연결 설정을 저장해야 합니다."); return
        }
        let client = WorkerClient(configuration: configuration)
        let diagnostics = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AnimationDiagnostics")
        defer { try? FileManager.default.removeItem(at: diagnostics) }
        for (name, format) in [("utyaduck", "animated"), ("utya3d", "video")] {
            if let selected = ProcessInfo.processInfo.environment["STICKERBRIDGE_LIVE_FORMAT"], selected != format { continue }
            let pack = try await client.pack(name: name)
            #expect(pack.stickerType == "regular")
            #expect(pack.stickers.contains { $0.format == format })
            let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let reader = LibraryReader(root: root.appendingPathComponent("library"))
            let coordinator = ImportCoordinator(writer: LibraryWriter(reader: reader), root: root.appendingPathComponent("jobs"))
            do { try await coordinator.install(pack, client: client) { _ in } }
            catch {
                let files = FileManager.default.enumerator(at: root.appendingPathComponent("jobs"), includingPropertiesForKeys: nil)
                let completed = Set((files?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "png" }.map { $0.deletingPathExtension().lastPathComponent })
                for sticker in pack.stickers where !completed.contains(sticker.id) && sticker.format == "video" {
                    do {
                        let original = try await client.asset(pack: pack.name, sticker: sticker)
                        let parsed = try StickerWebM.parse(original)
                        print("StickerBridge WebM diagnostic: \(sticker.id.prefix(8)), input=\(original.count), \(parsed.width)x\(parsed.height), packets=\(parsed.packets.count), duration=\(parsed.duration)")
                        _ = try await WebMConverter().convert(original)
                        print("StickerBridge WebM diagnostic: retry converted")
                    } catch {
                        print("StickerBridge WebM diagnostic: \(sticker.id.prefix(8)), failure=\(String(describing: error))")
                    }
                }
                throw error
            }
            let installed = try #require(reader.snapshot().packs.first)
            #expect(installed.stickers.count == pack.stickers.count)
            var animatedCount = 0, animatedBytes = 0
            for record in installed.stickers {
                let png = try Data(contentsOf: reader.file(record.pngPath))
                #expect(PNGValidation.isValid(png))
                if let path = record.animationPath {
                    let gif = try Data(contentsOf: reader.file(path))
                    #expect(GIFValidation.isValid(gif))
                    animatedCount += 1; animatedBytes += gif.count
                }
            }
            #expect(animatedCount > 0)
            print("StickerBridge live import: \(name), installed=\(installed.stickers.count), GIF=\(animatedCount), GIF bytes=\(animatedBytes)")
        }
    }
}

@MainActor
struct ReportedPackImportTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STICKERBRIDGE_LIVE_REPORTED_PACKS"] == "1"))
    func reportedPacksInstallAndFreshUpdate() async throws {
        guard let configuration = try ImportSettings.load() else {
            Issue.record("실기기 앱의 연결 설정이 필요합니다."); return
        }
        let client = WorkerClient(configuration: configuration)
        for name in ["dccon_real_1762389696919_by_tg_sticker_factory_bot", "mellborov"] {
            if let names = ProcessInfo.processInfo.environment["STICKERBRIDGE_LIVE_PACK_NAMES"], !names.split(separator: ",").contains(Substring(name)) { continue }
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ReportedPackImportTests/" + name)
            // Reuse only hash-named jobs from interrupted, temporary diagnostic runs.
            let fm = FileManager.default
            let jobs = root.appendingPathComponent("jobs")
            try fm.createDirectory(at: jobs, withIntermediateDirectories: true)
            for folder in (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? [] {
                for job in (try? fm.contentsOfDirectory(at: folder.appendingPathComponent("jobs"), includingPropertiesForKeys: nil)) ?? [] {
                    guard job.lastPathComponent.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { continue }
                    let destination = jobs.appendingPathComponent(job.lastPathComponent)
                    if !fm.fileExists(atPath: destination.path) { try? fm.copyItem(at: job, to: destination) }
                }
            }
            let reader = LibraryReader(root: root.appendingPathComponent("library"))
            let writer = LibraryWriter(reader: reader)
            let coordinator = ImportCoordinator(writer: writer, root: root.appendingPathComponent("jobs"))
            let pack = try await client.pack(name: name, refresh: true)
            print("StickerBridge starting reported pack: \(name), total=\(pack.stickers.count)")
            var priorFailures = await ImportFailureStore.shared.load(name: name)
            if name == "mellborov", let sticker = pack.stickers.first(where: { $0.id.hasPrefix("0c902f1f") }) {
                priorFailures = [ImportFailure(id: sticker.id, format: "video", stage: "変換", code: "timing", message: "", retryable: false)]
            }
            for failure in priorFailures.prefix(8) {
                guard let sticker = pack.stickers.first(where: { $0.id == failure.id }), sticker.format == "video" else { continue }
                do {
                    let bytes = try await client.asset(pack: name, sticker: sticker)
                    let detail = try await WebMConverter().diagnostics(bytes)
                    print("StickerBridge prior failure diagnosis: \(name), id=\(failure.id.prefix(8)), \(detail)")
                } catch { print("StickerBridge prior failure diagnosis: \(name), id=\(failure.id.prefix(8)), error=\(String(describing: error))") }
            }
            let start = ContinuousClock.now
            let result = try await coordinator.install(pack, client: client) { value in
                if (value.completed + value.failed) % 20 == 0 { print("StickerBridge reported progress: \(name), completed=\(value.completed), failed=\(value.failed), total=\(value.total)") }
            }
            let snapshot = try reader.snapshot()
            let records = snapshot.packs.flatMap(\.stickers)
            let qualities = records.compactMap(\.conversionQuality)
            let failures = await ImportFailureStore.shared.load(name: name)
            print("StickerBridge reported pack: \(name), total=\(pack.stickers.count), installed=\(result.installed), failed=\(result.failed), adjusted=\(qualities.count), duration=\(start.duration(to: .now))")
            for failure in failures { print("StickerBridge failure: \(name), id=\(failure.id.prefix(8)), format=\(failure.format), stage=\(failure.stage), code=\(failure.code)") }
            Attachment.record(try JSONEncoder().encode(failures), named: name + "-failures.json")
            #expect(result.installed > 0)
            for record in records {
                #expect(PNGValidation.isValid(try Data(contentsOf: reader.file(record.pngPath))))
                if let gif = record.animationPath { #expect(GIFValidation.isValid(url: try reader.file(gif))) }
                if let playback = record.playbackPath { #expect(GIFValidation.isValid(url: try reader.file(playback))) }
            }
            if result.failed == 0 {
                let fresh = try await client.pack(name: name, refresh: true)
                let updated = try await coordinator.install(fresh, client: client, updating: true) { _ in }
                #expect(updated.failed == 0)
                #expect(try reader.snapshot().packs.first?.lastCheckedAt != nil)
            }
            if result.failed == 0 { try? fm.removeItem(at: root) }
        }
    }
}
