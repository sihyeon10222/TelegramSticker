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
                .accessibilityIdentifier("selectionToggle")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// Animate content changes once; toolbar transitions belong to the system.
    static func update(_ action: () -> Void) {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .smooth(duration: 0.25), action)
    }
}

struct SelectionToggleButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                if active {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .transition(.blurReplace)
                } else {
                    Text(title)
                        .font(.body)
                        .transition(.blurReplace)
                }
            }
            .frame(width: active ? 44 : 64, height: 44)
            .foregroundStyle(active ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .glassEffect(active ? .regular.tint(.blue).interactive() : .regular.interactive(), in: .capsule)
        // Rehosting the toolbar during a split transition must not materialize
        // the glass from a point. Its existing shape follows the toolbar item.
        .glassEffectTransition(.identity)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: active)
        // Discard the navigation transition before the active-only animation
        // above restores the selection button's own width/color transition.
        .transaction { $0.animation = nil }
        .accessibilityLabel(active ? "완료" : title)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3), action)
    }
}
