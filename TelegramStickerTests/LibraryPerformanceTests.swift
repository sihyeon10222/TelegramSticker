import XCTest
import Darwin
@testable import TelegramSticker

final class LibraryPerformanceTests: XCTestCase {
    @MainActor
    func testThousandStickerLoadingThumbnailsAndCopyPreparation() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let reader = LibraryReader(root: root)
        let writer = LibraryWriter(reader: reader)
        // Exercise the production writer and 2,000 separate PNG/thumbnail paths.
        // Own bundled images only; no App Group, network, or user's library.
        for pack in 0..<10 {
            let inputs = try (0..<100).map { index in
                let sample = SampleSticker.all[index % SampleSticker.all.count]
                return LocalStickerInput(id: "sticker-\(index)", name: sample.name,
                                         url: try XCTUnwrap(sample.fileURL()))
            }
            try await writer.install(id: "load-pack-\(pack)", title: "Load pack \(pack)", stickers: inputs)
        }
        let started = ContinuousClock.now
        let initial = try reader.snapshot()
        print("StickerBridge 10 packs / 1000 stickers snapshot: \(started.duration(to: .now))")
        XCTAssertEqual(initial.packs.count, 10)
        XCTAssertEqual(initial.packs.flatMap(\.stickers).count, 1000)
        XCTAssertTrue(initial.warnings.isEmpty)
        var readings: [[String: Double]] = []
        for iteration in 0..<5 {
            await Task.yield()
            let started = ContinuousClock.now
            let before = Self.footprint()
            var peak = before
            var snapshotSeconds = 0.0
            var firstScreenSeconds = 0.0
            autoreleasepool {
                do {
                    let snapshotStart = ContinuousClock.now
                    let snapshot = try reader.snapshot()
                    snapshotSeconds = Self.seconds(snapshotStart.duration(to: .now))
                    let images = SampleStickerImages()
                    var writes = 0
                    let copier = StickerCopyService(writePNG: { _ in writes += 1 })
                    let records = snapshot.packs.flatMap { pack in pack.stickers.map { (pack.id, $0) } }
                    for (index, item) in records.prefix(200).enumerated() {
                        try autoreleasepool {
                            let (packID, record) = item
                            let sample = SampleSticker(id: packID + "." + record.id, name: record.name,
                                detail: packID, imageURL: try reader.file(record.pngPath),
                                thumbnailURL: try reader.file(record.thumbnailPath))
                            XCTAssertNotNil(images.thumbnail(for: sample))
                            if index % 20 == 0 {
                                XCTAssertEqual(copier.copyPNG(at: sample.fileURL(), isAllowed: true), .copied)
                            }
                            if index == 23 { firstScreenSeconds = Self.seconds(started.duration(to: .now)) }
                        }
                    }
                    XCTAssertEqual(writes, 10)
                    peak = Self.footprint()
                    images.removeAll()
                    XCTAssertEqual(try reader.snapshot().revision, snapshot.revision)
                } catch { XCTFail(error.localizedDescription) }
            }
            let reading = ["iteration": Double(iteration), "seconds": Self.seconds(started.duration(to: .now)),
                           "snapshotSeconds": snapshotSeconds, "first24Seconds": firstScreenSeconds, "beforeMiB": before,
                           "loadedMiB": peak, "afterMiB": Self.footprint()]
            readings.append(reading)
            print("StickerBridge performance: \(reading)")
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readings, options: [.prettyPrinted, .sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "1000 sticker loading and memory readings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Current physical footprint of this test process, not a keyboard extension memory limit.
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
