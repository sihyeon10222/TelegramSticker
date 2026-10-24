import SwiftUI
import UIKit

/// The visible toolbar control is both the action sender and popover anchor.
struct PackLinkShareButton: UIViewRepresentable {
    let text: String
    var disabled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "square.and.arrow.up")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body, scale: .large)
        button.configuration = configuration
        button.tintColor = .label
        button.adjustsImageSizeForAccessibilityContentSizeCategory = true
        button.accessibilityLabel = "Sticker Pack 링크 공유"
        button.accessibilityIdentifier = "sharePackLink"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.addTarget(context.coordinator, action: #selector(Coordinator.share(_:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.text = text
        button.isEnabled = isEnabled && !disabled && !text.isEmpty
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var text = ""
        private let presenter = PackLinkSharePresenter()

        @objc func share(_ button: UIButton) {
            guard button.isEnabled, !text.isEmpty else { return }
            presenter.share(PackLinkShareRequest(text: text), from: button, permittedArrowDirections: .up)
        }
    }
}

/// Present the native share controller directly from the visible content button.
struct PackLinksShareButton: View {
    let links: [String]
    let onCompleted: @MainActor () -> Void
    let onFailure: @MainActor (Error) -> Void
    @State private var presenter = PackLinkSharePresenter()

    var body: some View {
        Button {
            guard !presenter.isSharing else { return }
            do {
                presenter.share(try PackLinkShareRequest(links: links)) { completed in
                    if completed { onCompleted() }
                }
            }
            catch { onFailure(error) }
        } label: {
            Label("선택한 팩 공유", systemImage: "square.and.arrow.up")
                .background { PackLinkShareAnchor(presenter: presenter) }
        }
        .disabled(links.isEmpty)
    }
}

/// Keep shared content and any exported file alive until sharing finishes.
private final class PackLinkShareRequest {
    let id = UUID()
    let items: [Any]
    private let temporaryDirectory: URL?

    init(text: String) {
        items = [text]
        temporaryDirectory = nil
    }

    init(links: [String]) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("LinkList.stickerlinks")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do { try Data(links.joined(separator: "\n").utf8).write(to: url, options: .atomic) }
        catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        items = [url]
        temporaryDirectory = directory
    }

    deinit {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }
}

/// The home content button supplies its label bounds without a child controller.
private struct PackLinkShareAnchor: UIViewRepresentable {
    let presenter: PackLinkSharePresenter

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.presenter = presenter
        presenter.register(view)
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.presenter = presenter
        presenter.register(view)
    }

    final class AnchorView: UIView {
        weak var presenter: PackLinkSharePresenter?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            presenter?.register(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            presenter?.register(self)
        }
    }
}

/// Present from the button's window, never from a tiny background child
/// controller. Keep the request alive through cancellation and completion.
@MainActor
private final class PackLinkSharePresenter: NSObject, UIPopoverPresentationControllerDelegate {
    private weak var sourceView: UIView?
    private var request: PackLinkShareRequest?
    private var permittedArrowDirections: UIPopoverArrowDirection = .any
    private var onFinished: @MainActor (Bool) -> Void = { _ in }
    private var activity: UIActivityViewController?
    private var presentationScheduled = false

    var isSharing: Bool { request != nil }

    func register(_ view: UIView) {
        // Toolbar rehosting can briefly keep both old and new labels alive.
        // An unmounted copy must not replace the currently visible anchor.
        if view.window != nil || sourceView?.window == nil { sourceView = view }
        schedulePresentation()
    }

    func share(_ request: PackLinkShareRequest,
               from sourceView: UIView? = nil,
               permittedArrowDirections: UIPopoverArrowDirection = .any,
               onFinished: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !isSharing else { return }
        if let sourceView { self.sourceView = sourceView }
        self.request = request
        self.permittedArrowDirections = permittedArrowDirections
        self.onFinished = onFinished
        schedulePresentation()
    }

    func schedulePresentation() {
        guard request != nil, activity == nil, !presentationScheduled else { return }
        presentationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentationScheduled = false
            self.presentShareIfReady()
        }
    }

    private func presentShareIfReady() {
        guard let request, activity == nil, let sourceView,
              !sourceView.bounds.isEmpty, let window = sourceView.window,
              var controller = window.rootViewController else { return }
        while let presented = controller.presentedViewController {
            controller = presented
        }
        guard !controller.isBeingDismissed, !controller.isBeingPresented else {
            controller.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in
                self?.schedulePresentation()
            }
            return
        }

        let activity = UIActivityViewController(activityItems: request.items, applicationActivities: nil)
        // A link-list file must open the share chooser, rather than promoting
        // an Open in App action into the first screen.
        activity.allowsProminentActivity = false
        activity.completionWithItemsHandler = { [weak self, request] _, completed, _, _ in
            Task { @MainActor in self?.finish(id: request.id, completed: completed) }
        }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = .null
            popover.permittedArrowDirections = permittedArrowDirections
            popover.delegate = self
        }
        activity.presentationController?.delegate = self
        self.activity = activity
        controller.present(activity, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === activity,
              let request else { return }
        finish(id: request.id, completed: false)
    }

    private func finish(id: UUID, completed: Bool) {
        guard request?.id == id else { return }
        request = nil
        activity = nil
        let completion = onFinished
        onFinished = { _ in }
        completion(completed)
    }
}

struct PackTextShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = activity.view
            popover.sourceRect = CGRect(x: activity.view.bounds.midX, y: activity.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return activity
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
