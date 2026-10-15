import UIKit

@MainActor
final class PackDragSession {
    let id: String
    let button: PackTabButton
    let preview: UIView
    let originalPacks: [PackManifestV1]
    var viewportX: CGFloat
    init(id: String, button: PackTabButton, preview: UIView, originalPacks: [PackManifestV1], viewportX: CGFloat) {
        self.id = id; self.button = button; self.preview = preview
        self.originalPacks = originalPacks; self.viewportX = viewportX
    }
}
