import Foundation

/// Shared by preview and download requests. Cancellation removes queued work immediately.
actor RequestGate {
    private let limit: Int
    init(limit: Int = 3) { self.limit = max(1, limit) }
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                if active < limit { active += 1; continuation.resume() }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().1.resume() }
    }
    private func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.0 == id }) {
            waiting.remove(at: index).1.resume(throwing: CancellationError())
        }
    }
}

/// The Worker allows 20 pack lookups and 240 assets per minute. Pace requests
/// below those limits and share Retry-After across every parallel pack.
actor DownloadRequestBudget {
    static let shared = DownloadRequestBudget()
    private var packDates: [Date] = []
    private var assetDates: [Date] = []
    private var cooldown = Date.distantPast
    private var nextPack = Date.distantPast
    private var nextAsset = Date.distantPast
    func wait(asset: Bool) async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            packDates.removeAll { now.timeIntervalSince($0) >= 61 }
            assetDates.removeAll { now.timeIntervalSince($0) >= 61 }
            let dates = asset ? assetDates : packDates
            let cap = asset ? 210 : 18
            let window = dates.count >= cap ? dates[0].addingTimeInterval(61) : now
            let start = max(cooldown, max(window, asset ? nextAsset : nextPack))
            let delay = start.timeIntervalSince(now)
            if delay > 0 { try await Task.sleep(for: .seconds(delay)); continue }
            if asset { assetDates.append(now); nextAsset = now.addingTimeInterval(0.29) }
            else { packDates.append(now); nextPack = now.addingTimeInterval(0.15) }
            return
        }
    }
    func backOff(seconds: Int) { cooldown = max(cooldown, Date().addingTimeInterval(Double(max(1, seconds)))) }
}
