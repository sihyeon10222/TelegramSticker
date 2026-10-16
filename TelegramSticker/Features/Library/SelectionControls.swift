import SwiftUI
import UIKit

/// Keep the selection control in its own navigation-bar item.
struct SelectionControls: ToolbarContent {
    let id: String
    let active: Bool
    let title: String
    let toggle: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(id: id + ".toggle", placement: .topBarLeading) {
            SelectionToggleButton(active: active, title: title, action: toggle)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// Animate content changes once; toolbar transitions belong to the system.
    static func update(_ action: () -> Void) {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .smooth(duration: 0.25), action)
    }
}

/// Keep the material and label in one native control while UIKit rehosts the
/// toolbar during split-view transitions.
struct SelectionToggleButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        NativeSelectionToggleButton(active: active, title: title, reduceMotion: reduceMotion) {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3), action)
        }
            .frame(width: active ? 44 : 64, height: 44)
            .fixedSize()
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: active)
    }
}

private struct NativeSelectionToggleButton: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let active: Bool
    let title: String
    let reduceMotion: Bool
    let action: () -> Void

    func makeUIView(context: Context) -> Control {
        let button = Control(type: .system)
        button.accessibilityIdentifier = "selectionToggle"
        button.tintColor = .systemBlue
        button.addTarget(button, action: #selector(Control.activate), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: Control, context: Context) {
        button.action = action
        button.isEnabled = isEnabled
        button.accessibilityLabel = active ? "완료" : title
        let changed = button.active != active
        guard changed || button.selectionTitle != title else { return }
        let animate = button.active != nil && changed && !reduceMotion && button.window != nil
        button.active = active
        button.selectionTitle = title

        var configuration: UIButton.Configuration = active ? .prominentGlass() : .glass()
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = active ? .white : .label
        if active {
            configuration.image = UIImage(systemName: "checkmark")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
                .applying(UIImage.SymbolConfiguration(weight: .semibold))
        } else {
            var text = AttributedString(title)
            text.font = UIFont.preferredFont(forTextStyle: .body)
            configuration.attributedTitle = text
        }
        // Only selection changes update the native material. Sidebar changes
        // leave the existing UIButton and its configuration untouched.
        let apply = {
            button.configuration = configuration
            button.layoutIfNeeded()
        }
        if animate {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: apply)
        } else {
            UIView.performWithoutAnimation(apply)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Control, context: Context) -> CGSize? {
        CGSize(width: active ? 44 : 64, height: 44)
    }

    final class Control: UIButton {
        var action: (() -> Void)?
        var active: Bool?
        var selectionTitle: String?

        @objc func activate() { action?() }
    }
}
