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
