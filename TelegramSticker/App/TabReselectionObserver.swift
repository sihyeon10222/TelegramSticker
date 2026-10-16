import SwiftUI
import UIKit

struct TabReselectionObserver: UIViewControllerRepresentable {
    let librarySelectedAgain: () -> Void
    func makeUIViewController(context: Context) -> Observer { Observer(action: librarySelectedAgain) }
    func updateUIViewController(_ controller: Observer, context: Context) {
        controller.action = librarySelectedAgain
        controller.attach()
    }
    static func dismantleUIViewController(_ controller: Observer, coordinator: ()) { controller.detach() }

    final class Observer: UIViewController, UITabBarControllerDelegate {
        var action: () -> Void
        weak var observed: UITabBarController?
        weak var original: (any UITabBarControllerDelegate)?
        init(action: @escaping () -> Void) { self.action = action; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); attach() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); attach() }
        func attach() {
            guard let tabs = tabBarController, tabs.delegate !== self else { return }
            original = tabs.delegate
            observed = tabs
            tabs.delegate = self
        }
        func detach() {
            if observed?.delegate === self { observed?.delegate = original }
        }
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            let allowed = original?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
            if allowed, tabBarController.selectedViewController === viewController,
               tabBarController.viewControllers?.first === viewController { action() }
            return allowed
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
