import SwiftUI
import UIKit

struct PackLinkShareMenu: View {
    let links: [String]
    var title = "링크 공유"
    var body: some View {
        Menu {
            ShareLink(item: links.joined(separator: "\n")) {
                Label("Sticker Pack 링크 공유", systemImage: "link")
            }
            ShareLink(item: StickerLinkFile(text: links.joined(separator: "\n")), preview: SharePreview("Telegram 스티커 팩 링크 목록")) {
                Label("링크 목록 파일 공유", systemImage: "doc")
            }
        } label: { Label(title, systemImage: "square.and.arrow.up") }
            .disabled(links.isEmpty)
    }
}

struct PackLinksShareView: View {
    let links: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ShareLink(item: links.joined(separator: "\n")) { Label("Sticker Pack 링크 공유", systemImage: "link") }
                ShareLink(item: StickerLinkFile(text: links.joined(separator: "\n")), preview: SharePreview("스티커 팩 링크 목록")) {
                    Label("링크 목록 파일 공유", systemImage: "doc")
                }
            }
            .navigationTitle("팩 공유").navigationBarTitleDisplayMode(.inline)
            .toolbar { AppModalCloseToolbar { dismiss() } }
        }
    }
}


/// Present from the actual toolbar button so iPad anchors to its visible bounds.
struct PackLinkShareButton: View {
    let text: String
    var disabled = false

    var body: some View {
        #if targetEnvironment(macCatalyst)
        CatalystPackShareButton(text: text, disabled: disabled || text.isEmpty)
            .frame(width: 36, height: 36)
        #else
        ShareLink(item: text) {
            Label("Sticker Pack 링크 공유", systemImage: "square.and.arrow.up")
        }
        .labelStyle(.iconOnly)
        .disabled(disabled || text.isEmpty)
        .accessibilityIdentifier("sharePackLink")
        #endif
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
