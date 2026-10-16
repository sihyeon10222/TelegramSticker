import SwiftUI
import UIKit

/// Reassert expansion after UIKit finishes its compact-to-split transition.
struct LibraryRotationObserver: UIViewControllerRepresentable {
    let openSidebar: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(openSidebar: openSidebar) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.openSidebar = openSidebar
    }
    final class Controller: UIViewController {
        var openSidebar: () -> Void
        private var wasLandscape = false
        private var transitioning = false
        private var transitionGeneration = 0
        init(openSidebar: @escaping () -> Void) {
            self.openSidebar = openSidebar
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard !transitioning, let window = view.window else { return }
            let landscape = window.bounds.width > window.bounds.height
            if landscape && !wasLandscape {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window = self.view.window,
                          window.bounds.width > window.bounds.height else { return }
                    self.openSidebar()
                }
            }
            wasLandscape = landscape
        }
        override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            transitioning = true
            transitionGeneration += 1
            let generation = transitionGeneration
            let enteringLandscape = size.width > size.height && !wasLandscape
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self, self.transitionGeneration == generation else { return }
                self.transitioning = false
                guard let window = self.view.window else { return }
                self.wasLandscape = window.bounds.width > window.bounds.height
                if enteringLandscape && self.wasLandscape {
                    DispatchQueue.main.async { [weak self] in self?.openSidebar() }
                }
            }
        }
    }
}

// Resolve markers from the visible navigation bar, not from retained SwiftUI
// toolbar values: UIKit can reuse those values when the selected pack changes.
struct PackTitleBoundary: UIViewRepresentable {
    let leading: Bool

    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ view: Marker, context: Context) { view.leading = leading }

    final class Marker: UIView {
        var leading = false
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

struct LandscapePackTitle: UIViewRepresentable {
    let title: String

    func makeUIView(context: Context) -> TitleView { TitleView() }

    func updateUIView(_ view: TitleView, context: Context) {
        view.label.text = title
        view.invalidateIntrinsicContentSize()
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: TitleView, coordinator: ()) { view.stop() }

    final class TitleView: UIView {
        let label = UILabel()
        private var displayLink: CADisplayLink?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            label.font = .preferredFont(forTextStyle: .headline)
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.numberOfLines = 1
            label.clipsToBounds = true
            label.isUserInteractionEnabled = false
            label.accessibilityTraits = .header
            addSubview(label)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var intrinsicContentSize: CGSize { label.intrinsicContentSize }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            if window != nil {
                let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
                alignTitle()
            }
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
            label.removeFromSuperview()
        }

        deinit { displayLink?.invalidate() }

        override func layoutSubviews() {
            super.layoutSubviews()
            alignTitle()
        }

        private func descendants<T: UIView>(of view: UIView, matching type: T.Type) -> [T] {
            view.subviews.flatMap { child -> [T] in
                guard !child.isHidden, child.alpha > 0.01 else { return [] }
                return (child as? T).map { [$0] } ?? descendants(of: child, matching: type)
            }
        }

        fileprivate func alignTitle() {
            guard let window else { return }
            let host = convert(bounds, to: window)
            let markers = descendants(of: window, matching: PackTitleBoundary.Marker.self).filter {
                let frame = $0.convert($0.bounds, to: window)
                return frame.width > 0 && abs(frame.midY - host.midY) < 44
            }
            guard let leading = markers.first(where: { $0.leading }),
                  let trailing = markers.first(where: { !$0.leading }) else {
                showInHost()
                return
            }
            // SwiftUI toolbar content need not descend from UINavigationBar.
            // Use the actual actions' common ancestor rather than requiring one.
            var ancestor: UIView? = leading.superview
            while let candidate = ancestor,
                  !(trailing.isDescendant(of: candidate) && isDescendant(of: candidate)) {
                ancestor = candidate.superview
            }
            guard let container = ancestor else { showInHost(); return }
            let leadingFrame = leading.convert(leading.bounds, to: container)
            let trailingFrame = trailing.convert(trailing.bounds, to: container)
            let left = leadingFrame.maxX + 8
            let right = trailingFrame.minX - 8
            guard right > left else { showInHost(); return }
            let height = label.intrinsicContentSize.height
            let centerY = (leadingFrame.midY + trailingFrame.midY) / 2
            let frame = CGRect(x: left, y: centerY - height / 2, width: right - left, height: height)
            if label.superview !== container { container.addSubview(label) }
            if label.frame != frame { label.frame = frame }
        }

        private func showInHost() {
            // Keep the title visible while toolbar actions are being mounted.
            if label.superview !== self { addSubview(label) }
            label.frame = bounds
        }

        private final class WeakTarget {
            weak var view: TitleView?
            init(_ view: TitleView) { self.view = view }
            @objc func tick() { view?.alignTitle() }
        }
    }
}
