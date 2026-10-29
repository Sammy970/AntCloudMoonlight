import SwiftUI

/// Login gate shared by both apps; each platform provides its own `HomeView(api:)`.
struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        switch auth.state {
        case .restoring:
            ProgressView("Signing in…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loggedOut:
            LoginView()
        case .loggedIn:
            HomeView(api: auth.api)
        }
    }
}
