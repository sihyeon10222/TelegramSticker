import UIKit

final class PackTabScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { view is UIControl || super.touchesShouldCancel(in: view) }
}
