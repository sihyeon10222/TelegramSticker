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
        .sharedBackgroundVisibility(.visible)
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
        // Let the navigation bar move the button and its glass together when
        // split-view columns change. A custom glassEffect on toolbar content
        // can collapse into a white dot while UIKit rehosts that content.
        Button(role: active ? .confirm : nil, action: toggle) {
            if active { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
            else { Text(title) }
        }
        .tint(active ? .blue : nil)
        .accessibilityLabel(active ? "완료" : title)
    }

    private func toggle() {
        #if targetEnvironment(macCatalyst)
        action()
        #else
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3), action)
        #endif
    }
}
