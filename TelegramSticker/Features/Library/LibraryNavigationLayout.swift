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

/// Measure the real action edges in one coordinate space, including during rotation.
final class PackTitleLayout {
    weak var leading: UIView?
    weak var trailing: UIView?
}

struct PackTitleBoundary: UIViewRepresentable {
    let layout: PackTitleLayout
    let leading: Bool
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if leading { layout.leading = view } else { layout.trailing = view }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        // SwiftUI may reuse an existing marker with a newly evaluated layout value.
        if leading { layout.leading = view } else { layout.trailing = view }
    }
}

struct PackCenteredTitle: UIViewRepresentable {
    let title: String
    let layout: PackTitleLayout
    func makeUIView(context: Context) -> TitleView { TitleView(layout: layout) }
    func updateUIView(_ view: TitleView, context: Context) {
        view.label.text = title
        view.invalidateIntrinsicContentSize()
        view.updatePosition()
    }
    final class TitleView: UIView {
        let label = UILabel()
        let layout: PackTitleLayout
        private var displayLink: CADisplayLink?
        private let ticker = Ticker()
        final class Ticker: NSObject {
            weak var owner: TitleView?
            @objc func tick() { owner?.updatePosition() }
        }
        init(layout: PackTitleLayout) {
            self.layout = layout
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            label.font = .preferredFont(forTextStyle: .headline)
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.isUserInteractionEnabled = false
            addSubview(label)
            ticker.owner = self
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var intrinsicContentSize: CGSize {
            CGSize(width: min(200, label.intrinsicContentSize.width), height: 44)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            updatePosition()
        }
        private func showFallback() {
            if label.superview !== self { addSubview(label) }
            label.isHidden = false
            label.frame = bounds
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            displayLink?.invalidate()
            displayLink = nil
            if window == nil { label.removeFromSuperview() }
            if window != nil {
                let link = CADisplayLink(target: ticker, selector: #selector(Ticker.tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }
        deinit { displayLink?.invalidate(); label.removeFromSuperview() }
        func updatePosition() {
            guard let window, let leading = layout.leading, let trailing = layout.trailing,
                  leading.window === window, trailing.window === window else {
                showFallback()
                return
            }
            // SwiftUI can host toolbar items in separate hierarchies. Use the
            // actions' common ancestor instead of assuming a UINavigationBar parent.
            var leadingAncestors = Set<ObjectIdentifier>()
            var ancestor: UIView? = leading.superview
            while let view = ancestor {
                leadingAncestors.insert(ObjectIdentifier(view))
                ancestor = view.superview
            }
            ancestor = trailing.superview
            while let view = ancestor, !leadingAncestors.contains(ObjectIdentifier(view)) {
                ancestor = view.superview
            }
            guard let bar = ancestor else {
                showFallback()
                return
            }
            if label.superview !== bar { bar.addSubview(label) }
            let leftFrame = leading.convert(leading.bounds, to: bar)
            let rightFrame = trailing.convert(trailing.bounds, to: bar)
            let frame = CGRect(x: leftFrame.maxX + 8,
                               y: leftFrame.midY - 22,
                               width: max(0, rightFrame.minX - leftFrame.maxX - 16), height: 44)
            label.isHidden = frame.width <= 0
            if label.frame != frame { label.frame = frame }
        }
    }
}
