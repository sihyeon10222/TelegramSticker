import SwiftUI
import UIKit

/// Attach the accessory to the cell, outside its animated editing content view.
struct FixedPackChevron: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ view: AnchorView, context: Context) { view.attach() }
    static func dismantleUIView(_ view: AnchorView, coordinator: ()) { view.chevron.removeFromSuperview() }

    final class AnchorView: UIView {
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            chevron.tintColor = .tertiaryLabel
            chevron.contentMode = .center
            chevron.isUserInteractionEnabled = false
            chevron.isAccessibilityElement = false
            chevron.translatesAutoresizingMaskIntoConstraints = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { chevron.removeFromSuperview() } else { attach() }
        }
        override func layoutSubviews() { super.layoutSubviews(); attach() }
        func attach() {
            var ancestor = superview
            while let view = ancestor {
                if view is UICollectionViewCell || view is UITableViewCell {
                    guard chevron.superview !== view else { return }
                    chevron.removeFromSuperview()
                    UIView.performWithoutAnimation {
                        view.addSubview(chevron)
                        NSLayoutConstraint.activate([
                            chevron.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                            chevron.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                            chevron.widthAnchor.constraint(equalToConstant: 12),
                            chevron.heightAnchor.constraint(equalToConstant: 20)
                        ])
                        view.layoutIfNeeded()
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
