import SwiftUI
import UIKit

/// Give each action its own navigation-bar item. The bar owns sizing, glass,
/// and insertion transitions; a resizing custom-view HStack cannot coordinate
/// those transitions with the navigation bar's UIKit layout.
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
    let active: Bool
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer {
            Button(action: action) {
                ZStack {
                    Text(title).opacity(active ? 0 : 1)
                    Image(systemName: "checkmark").fontWeight(.semibold).opacity(active ? 1 : 0)
                }
                .font(.body)
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: active ? 44 : 56, height: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(active ? .blue : .clear).interactive(), in: Capsule())
            .glassEffectID("selectionToggle", in: glassNamespace)
            .accessibilityLabel(active ? "완료" : title)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: active)
    }
}
