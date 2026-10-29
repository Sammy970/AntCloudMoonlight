import SwiftUI

extension Color {
    /// AntCloud brand blue, sampled from the official icon.
    static let antBlue = Color(red: 0.29, green: 0.53, blue: 0.91)
}

enum KeyboardKind { case email, phone, oneTimeCode, number }

extension View {
    /// Plain text-link button: `.link` on macOS, borderless on iOS.
    @ViewBuilder
    func textLinkStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }

    /// Picks a suitable software keyboard on iOS; no-op on macOS.
    @ViewBuilder
    func keyboard(_ kind: KeyboardKind) -> some View {
        #if os(iOS)
        switch kind {
        case .email:
            keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .phone:
            keyboardType(.phonePad).textContentType(.telephoneNumber)
        case .oneTimeCode:
            keyboardType(.numberPad).textContentType(.oneTimeCode)
        case .number:
            keyboardType(.numberPad)
        }
        #else
        self
        #endif
    }
}

/// The app's own icon: the bundle icon on macOS; on iOS the bundled `AntCloudLogo` image
/// (falls back to a cloud glyph when the app doesn't ship it).
struct AppIconImage: View {
    var body: some View {
        #if os(macOS)
        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
        #else
        if let logo = UIImage(named: "AntCloudLogo") {
            Image(uiImage: logo).resizable().interpolation(.high)
        } else {
            Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(Color.antBlue)
        }
        #endif
    }
}

extension View {
    /// Sign-in fields: large rounded-border fields on macOS, filled rounded fields on iOS.
    @ViewBuilder
    func loginFieldStyle() -> some View {
        #if os(macOS)
        textFieldStyle(.roundedBorder).controlSize(.large)
        #else
        textFieldStyle(FilledFieldStyle())
        #endif
    }
}

#if os(iOS)
private struct FilledFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
#endif

extension View {
    /// Lets the view run under a hidden, transparent window title bar (macOS 15+); no-op elsewhere.
    @ViewBuilder
    func transparentTitleBar() -> some View {
        #if os(macOS)
        if #available(macOS 15, *) {
            toolbar(removing: .title).toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Liquid Glass

/// Glass is used on iOS/macOS 26+. Debug window snapshots (`ANTCLOUD_SNAPSHOT`) can't draw it,
/// so they get the pre-26 look instead.
private let glassAllowed: Bool = {
    #if DEBUG && os(macOS)
    return ProcessInfo.processInfo.environment["ANTCLOUD_SNAPSHOT"] == nil
    #else
    return true
    #endif
}()

extension View {
    /// A Liquid Glass panel on iOS/macOS 26+; a material card on earlier systems.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, macOS 26, *), glassAllowed {
            glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
    }

    /// Capsule-shaped Liquid Glass, for chips and small strips.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, *), glassAllowed {
            glassEffect(Self.glass(tint: tint, interactive: interactive), in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    /// The one main action: tinted glass on 26+, bordered-prominent before.
    @ViewBuilder
    func primaryGlassButton() -> some View {
        if #available(iOS 26, macOS 26, *), glassAllowed {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Secondary actions: clear, untinted glass on 26+ (the app's blue tint is kept for the one
    /// main action), bordered before.
    @ViewBuilder
    func secondaryGlassButton() -> some View {
        if #available(iOS 26, macOS 26, *), glassAllowed {
            buttonStyle(.glass).tint(nil)
        } else {
            buttonStyle(.bordered)
        }
    }

    @available(iOS 26, macOS 26, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Groups nearby glass shapes so they blend and morph together on 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, macOS 26, *), glassAllowed {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
