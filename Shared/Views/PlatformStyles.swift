import SwiftUI

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
