import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

struct PackLinkReorderDropDelegate: DropDelegate {
    let active: Bool
    let move: () -> Void
    let finish: () -> Void
    func validateDrop(info: DropInfo) -> Bool { active }
    func dropEntered(info: DropInfo) { if active { move() } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: active ? .move : .cancel) }
    func performDrop(info: DropInfo) -> Bool {
        guard active else { return false }
        finish()
        return true
    }
}
