import UIKit

final class PackTabButton: UIButton {
    var packID: String?
    var posterTask: Task<Void, Never>?
    var posterReady = false
    deinit { posterTask?.cancel() }
}
