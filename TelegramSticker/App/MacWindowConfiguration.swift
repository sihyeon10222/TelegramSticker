#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Configure the actual Catalyst scene as well as SwiftUI's content sizing policy.
struct MacWindowConfiguration: UIViewRepresentable {
    static let minimumSize = CGSize(width: 640, height: 480)

    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ view: AnchorView, context: Context) { view.configureWindow() }

    final class AnchorView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureWindow()
            // SwiftUI may finish applying its scene preferences after attachment.
            DispatchQueue.main.async { [weak self] in self?.configureWindow() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            configureWindow()
        }
        func configureWindow() {
            window?.windowScene?.titlebar?.titleVisibility = .hidden
            guard let restrictions = window?.windowScene?.sizeRestrictions else { return }
            let maximum = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if restrictions.maximumSize != maximum { restrictions.maximumSize = maximum }
            if restrictions.minimumSize != MacWindowConfiguration.minimumSize {
                restrictions.minimumSize = MacWindowConfiguration.minimumSize
            }
            if !restrictions.allowsFullScreen { restrictions.allowsFullScreen = true }
        }
    }
}
#endif
