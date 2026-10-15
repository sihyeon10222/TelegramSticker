import UIKit

@MainActor
final class PackDragScrollProxy: NSObject {
    weak var owner: KeyboardViewController?
    init(owner: KeyboardViewController) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) { owner?.stepPackDrag(link) }
}
