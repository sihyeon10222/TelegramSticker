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
        #if targetEnvironment(macCatalyst)
        buttonStyle(CatalystMaterialButtonStyle(prominent: prominent, tint: tint))
        #else
        if let tint {
            if prominent { buttonStyle(.glassProminent).tint(tint) }
            else { buttonStyle(.glass).tint(tint) }
        } else {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        }
        #endif
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

struct AppGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        #if targetEnvironment(macCatalyst)
        content()
        #else
        GlassEffectContainer(spacing: spacing, content: content)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct CatalystMaterialButtonStyle: ButtonStyle {
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
            .background {
                ZStack {
                    Capsule().fill(.regularMaterial)
                    // Keep the tint above the material so prominent labels retain contrast.
                    if prominent {
                        Capsule().fill(isEnabled ? color : Color.secondary.opacity(0.12))
                    }
                }
            }
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(isEnabled ? 0.14 : 0.07), lineWidth: 0.5)
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed && isEnabled ? 0.75 : 1)
    }
}
#endif
