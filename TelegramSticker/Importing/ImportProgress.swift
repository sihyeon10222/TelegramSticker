import Foundation

nonisolated struct ImportProgress: Sendable {
    let completed: Int
    let total: Int
    let failed: Int
    let applied: Bool
    init(completed: Int, total: Int, failed: Int, applied: Bool = false) {
        self.completed = completed; self.total = total; self.failed = failed; self.applied = applied
    }
    var installedCount: Int { min(max(0, total), max(0, completed)) }
    var fraction: Double {
        let fraction = total > 0 ? Double(installedCount) / Double(total) : 0
        return applied ? fraction : min(0.99, fraction)
    }
    var percentage: Int { Int(fraction * 100) }
    var displayText: String { "\(installedCount)/\(max(0, total)) (\(percentage)%) 실패 \(max(0, failed))" }
}
