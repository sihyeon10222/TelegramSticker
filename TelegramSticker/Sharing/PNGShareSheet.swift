import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SharedPNG: Identifiable { let id = UUID(); let data: Data; var type = "public.png" }

/// A stable PNG data representation; no temporary source file can disappear during sharing.
private final class PNGActivityItem: NSObject, UIActivityItemSource {
    let data: Data
    let type: String
    init(data: Data, type: String) { self.data = data; self.type = type }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { data }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { data }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String { type }
}

struct PNGShareSheet: UIViewControllerRepresentable {
    let data: Data
    var type = "public.png"
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [PNGActivityItem(data: data, type: type)], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "pngShareSheet"
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
