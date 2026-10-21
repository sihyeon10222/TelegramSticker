import SwiftUI
import Combine
import UIKit

/// Present from the actual toolbar button so iPad anchors to its visible bounds.
struct PackLinkShareButton: View {
    let text: String
    var disabled = false
    @StateObject private var presenter = PackLinkSharePresenter()

    var body: some View {
        #if targetEnvironment(macCatalyst)
        CatalystPackShareButton(text: text, disabled: disabled || text.isEmpty)
            .frame(width: 36, height: 36)
        #else
        Button { presenter.present(text: text) } label: {
            Label("Sticker Pack 링크 공유", systemImage: "square.and.arrow.up")
        }
        .background(PackLinkShareAnchor(presenter: presenter))
        .labelStyle(.iconOnly)
        .disabled(disabled || text.isEmpty)
        .accessibilityIdentifier("sharePackLink")
        #endif
    }


}

@MainActor
private final class PackLinkSharePresenter: ObservableObject {
    weak var sourceView: UIView?

    func present(text: String) {
        guard let sourceView, let window = sourceView.window else { return }
        var responder: UIResponder? = sourceView
        while responder != nil && !(responder is UIViewController) {
            responder = responder?.next
        }
        guard let controller = responder as? UIViewController,
              controller.view.window === window,
              controller.presentedViewController == nil else { return }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
            popover.permittedArrowDirections = .any
        }
        controller.present(activity, animated: true)
    }
}

private struct PackLinkShareAnchor: UIViewRepresentable {
    let presenter: PackLinkSharePresenter

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        presenter.sourceView = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        presenter.sourceView = view
    }
}

#if targetEnvironment(macCatalyst)
/// The visible UIKit control is also the popover source; no detached SwiftUI anchor.
private struct CatalystPackShareButton: UIViewRepresentable {
    let text: String
    let disabled: Bool

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.accessibilityLabel = "Sticker Pack 링크 공유"
        button.accessibilityIdentifier = "sharePackLink"
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.isEnabled = !disabled
        button.removeAction(identifiedBy: UIAction.Identifier("sharePackLink"), for: .touchUpInside)
        button.addAction(UIAction(identifier: UIAction.Identifier("sharePackLink")) { [weak button] _ in
            guard let button, let window = button.window else { return }
            var responder: UIResponder? = button
            while responder != nil && !(responder is UIViewController) {
                responder = responder?.next
            }
            guard let presenter = responder as? UIViewController,
                  presenter.view.window === window else { return }
            let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = button
                popover.sourceRect = button.bounds
                popover.permittedArrowDirections = .up
            }
            presenter.present(activity, animated: true)
        }, for: .touchUpInside)
    }
}
#endif

struct PackTextShareSheet: UIViewControllerRepresentable {
    let text: String
    var fileURL: URL? = nil
    var onCompleted: @MainActor () -> Void = {}
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activity = UIActivityViewController(activityItems: fileURL.map { [$0 as Any] } ?? [text], applicationActivities: nil)
        let onCompleted = onCompleted
        activity.completionWithItemsHandler = { _, completed, _, _ in
            if completed { Task { @MainActor in onCompleted() } }
        }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = activity.view
            popover.sourceRect = CGRect(x: activity.view.bounds.midX, y: activity.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return activity
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
