import Foundation

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
