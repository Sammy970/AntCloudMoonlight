import Foundation

@MainActor
final class AuthStore: ObservableObject {
    enum State { case restoring, loggedOut, loggedIn }

    @Published private(set) var state: State = .restoring
    @Published private(set) var profile: UserProfile?

    let api = APIClient()
    private static let refreshAccount = "refreshToken"

    init() {
        api.refreshHandler = { [weak self] in await self?.refreshAccessToken() }
    }

    var accessToken: String? { api.accessToken }

    #if DEBUG
    /// Screenshot mode: shows the signed-in UI with a fake profile, without touching the Keychain.
    func previewSignIn(_ profile: UserProfile?) {
        self.profile = profile
        state = profile == nil ? .loggedOut : .loggedIn
    }
    #endif

    func restore() async {
        guard Keychain.get(Self.refreshAccount) != nil, await refreshAccessToken() != nil else {
            state = .loggedOut
            return
        }
        await finishLogin()
    }

    func login(email: String, password: String) async throws {
        try await adopt(api.login(email: email, password: password))
    }

    func sendOTP(phone: String) async throws {
        try await api.sendOTP(phone: Self.normalizedPhone(phone))
    }

    func verifyOTP(phone: String, otp: String) async throws {
        try await adopt(api.phoneLogin(phone: Self.normalizedPhone(phone), otp: otp))
    }

    /// The API expects E.164; like the Windows client, bare Indian numbers get a +91 prefix.
    static func normalizedPhone(_ input: String) -> String {
        let trimmed = input.filter { !$0.isWhitespace && $0 != "-" }
        if trimmed.hasPrefix("+") { return trimmed }
        var digits = trimmed
        if digits.count == 11, digits.hasPrefix("0") { digits.removeFirst() }
        if digits.count == 12, digits.hasPrefix("91") { digits.removeFirst(2) }
        return "+91" + digits
    }

    func forgotPassword(email: String) async throws {
        try await api.forgotPassword(email: email)
    }

    func reloadProfile() async {
        profile = try? await api.me()
    }

    func logout() {
        Keychain.delete(Self.refreshAccount)
        api.accessToken = nil
        profile = nil
        state = .loggedOut
    }

    private func adopt(_ tokens: (access: String, refresh: String?)) async {
        api.accessToken = tokens.access
        if let refresh = tokens.refresh { Keychain.set(refresh, for: Self.refreshAccount) }
        await finishLogin()
    }

    private func finishLogin() async {
        profile = try? await api.me()
        state = .loggedIn
    }

    private func refreshAccessToken() async -> String? {
        guard let refresh = Keychain.get(Self.refreshAccount),
              let tokens = try? await api.refresh(refreshToken: refresh) else { return nil }
        api.accessToken = tokens.access
        if let newRefresh = tokens.refresh { Keychain.set(newRefresh, for: Self.refreshAccount) }
        return tokens.access
    }
}
