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
