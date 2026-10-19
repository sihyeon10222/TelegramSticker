import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor @Observable
final class OptimizationCenter {
    static let shared = OptimizationCenter()
    var current: OptimizationSession?
    var presented: OptimizationSession?
    func session(for request: OptimizationRequest) -> OptimizationSession {
        if let current, current.running || current.request.id == request.id { return current }
        let session = OptimizationSession(request: request)
        current = session
        return session
    }
    func presentCurrent() { presented = current }
}
