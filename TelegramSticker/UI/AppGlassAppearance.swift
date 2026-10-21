import SwiftUI

extension View {
    /// Keep Catalyst sheets from sampling the presenting window through a second
    /// translucent surface. Content and toolbar materials keep their own effects.
    @ViewBuilder func appModalBackground() -> some View {
        #if targetEnvironment(macCatalyst)
        presentationBackground(Color(uiColor: .systemBackground))
        #else
        self
        #endif
    }

    /// Catalyst's iPad idiom can corrupt stretched Liquid Glass button surfaces.
    /// Keep the shared layout while using an ordinary material surface on Mac.
    @ViewBuilder func appGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        buttonStyle(AppQuietGlassButtonStyle(prominent: prominent, tint: tint))
    }

    @ViewBuilder func appGlassPanel(cornerRadius: CGFloat) -> some View {
        #if targetEnvironment(macCatalyst)
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        #else
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }
}

/// Sheet toolbar buttons need the same Catalyst fallback as content buttons.
/// Hide only their native chrome; the custom material style draws the capsule.
struct AppModalCloseToolbar: ToolbarContent {
    var title = "닫기"
    var accessibilityID = "closeSheet"
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            #if targetEnvironment(macCatalyst)
            Button(title, action: action)
                .appGlassButton()
                .controlSize(.regular)
                .fixedSize()
                .accessibilityIdentifier(accessibilityID)
            #else
            Button(title, action: action)
                .accessibilityIdentifier(accessibilityID)
            #endif
        }
        #if targetEnvironment(macCatalyst)
        .sharedBackgroundVisibility(.hidden)
        #endif
    }
}

private struct AppQuietGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    let prominent: Bool
    let tint: Color?

    private var padding: (horizontal: CGFloat, vertical: CGFloat, height: CGFloat) {
        switch controlSize {
        case .mini: (9, 4, 24)
        case .small: (12, 6, 30)
        case .large: (20, 11, 44)
        case .extraLarge: (24, 14, 52)
        default: (14, 8, 36)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let color = tint ?? (configuration.role == .destructive ? Color.red : Color.accentColor)
        configuration.label
            .padding(.horizontal, padding.horizontal)
            .padding(.vertical, padding.vertical)
            .frame(minHeight: padding.height)
            .foregroundStyle(isEnabled ? (prominent ? Color.white : configuration.role == .destructive ? Color.red : Color.primary) : Color.secondary)
            .modifier(AppQuietButtonSurface(color: prominent ? (isEnabled ? color : Color.secondary.opacity(0.12)) : nil))
            .contentShape(Capsule())
            .opacity(configuration.isPressed && isEnabled ? 0.75 : 1)
    }
}

private struct AppQuietButtonSurface: ViewModifier {
    let color: Color?
    @ViewBuilder func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.background {
            ZStack {
                Capsule().fill(.regularMaterial)
                if let color { Capsule().fill(color) }
            }
        }
        #else
        // Decorative glass only: native glass button styles and interactive
        // glass own their system press feedback, independently of our haptic code.
        content.glassEffect(color.map { .regular.tint($0) } ?? .regular, in: .capsule)
        #endif
    }
}

/// A switch drawn with a plain button avoids the native switch's selection haptic.
struct AppQuietToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 27, height: 27).padding(2)
                    }
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text("켬") : Text("끔"))
        .accessibilityAddTraits(configuration.isOn ? [.isToggle, .isSelected] : [.isToggle])
    }
}
