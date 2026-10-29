import Combine
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted by MainFrameViewController when Moonlight starts pairing; userInfo["pin"].
    static let antCloudPairingPIN = Notification.Name("AntCloudPairingPIN")
}

/// Entry points used from Objective-C (`NSClassFromString(@"AntCloudPanel")`).
@objc(AntCloudPanel)
final class AntCloudPanel: NSObject {
    /// Cloud PC address left by Play for MainFrameViewController to connect to once the panel closes.
    @MainActor static var pendingConnectAddress: String?

    @objc @MainActor static func makeViewController() -> UIViewController {
        let store = AntCloudStore.shared
        let controller = PanelHostingController(rootView: AnyView(AntCloudRootView(store: store).environmentObject(store.auth)))
        controller.modalPresentationStyle = .fullScreen
        // Switch to portrait before presenting: UIKit checks orientations at presentation time
        // and aborts if the app's mask and the controller's share none.
        store.panelVisible = true
        return controller
    }

    /// Read by AppDelegate's supportedInterfaceOrientationsForWindow.
    @objc @MainActor static var orientationMask: NSNumber {
        let mask: UIInterfaceOrientationMask = AntCloudStore.shared.panelVisible ? .portrait : .landscape
        return NSNumber(value: mask.rawValue)
    }

    /// Rotates the window to match `orientationMask` right away.
    @MainActor static func applyOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: UIInterfaceOrientationMask(rawValue: orientationMask.uintValue)))
    }

    @objc @MainActor static func takePendingConnectAddress() -> String? {
        defer { pendingConnectAddress = nil }
        return pendingConnectAddress
    }
}

/// Hosts the panel in portrait and switches the app back to landscape when it closes.
/// It accepts any orientation itself, so the app-wide mask (`orientationMask`) alone decides
/// and the two can never end up with nothing in common.
private final class PanelHostingController: UIHostingController<AnyView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Back in AntCloud: the stream (and its overlay) is over.
        StreamOverlayWindow.shared.end()
        AntCloudStore.shared.panelVisible = true
        AntCloudPanel.applyOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AntCloudStore.shared.panelVisible = false
        AntCloudPanel.applyOrientation()
    }
}

/// Owns login and the cloud-PC session for the life of the app, so the session keeps running
/// while the panel is dismissed and Moonlight is streaming.
@MainActor
final class AntCloudStore: ObservableObject {
    static let shared = AntCloudStore()

    let auth = AuthStore()
    let session: SessionService
    /// True while the panel is on screen; otherwise session notices are shown over Moonlight.
    /// Starts true so the app launches in portrait straight into AntCloud.
    var panelVisible = true
    private var noticeSubscription: AnyCancellable?

    private init() {
        session = SessionService(api: auth.api)
        session.onSessionExpired = { [weak self] in self?.auth.logout() }
        noticeSubscription = session.$notice.compactMap { $0 }.sink { [weak self] notice in
            Log.info("[panel] notice: \(notice.title) — \(notice.message)")
            guard let self, !panelVisible else { return }
            Self.presentOverMoonlight(notice)
        }
        NotificationCenter.default.addObserver(forName: .antCloudPairingPIN, object: nil, queue: .main) { note in
            guard let pin = note.userInfo?["pin"] as? String else { return }
            Task { @MainActor in await AntCloudStore.shared.submitPairingPIN(pin) }
        }
        if !startPreview() { Task { await auth.restore() } }
    }

    /// Debug builds only. Launch with `ANTCLOUD_PREVIEW=login` or `home:<phase>` to show a state with a
    /// sample account (no Keychain, no API), `ANTCLOUD_APPEARANCE=light|dark`, and `ANTCLOUD_SNAPSHOT=<name>`
    /// to save the screen to Documents/<name>.png a few seconds after launch.
    private func startPreview() -> Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let value = env["ANTCLOUD_PREVIEW"] else { return false }
        let renew = ISO8601DateFormatter().string(from: .now.addingTimeInterval(12 * 86_400))
        auth.previewSignIn(value == "login" ? nil : UserProfile(json: [
            "firstName": "Samyak", "email": "player@example.com", "currentPlan": "premiumNyt",
            "renewDate": renew, "totalTimeMonth": 3600, "timeUsedMonth": 1290,
        ]))
        let phases: [String: SessionService.Phase] = [
            "idle": .idle, "connecting": .connecting, "queued": .queued(position: 3), "booting": .booting,
            "ready": .ready, "pairing": .pairing, "streaming": .streaming,
        ]
        if value.hasPrefix("home:"), let phase = phases[String(value.dropFirst(5))] { session.previewPhase(phase) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let style: UIUserInterfaceStyle = env["ANTCLOUD_APPEARANCE"] == "light" ? .light : env["ANTCLOUD_APPEARANCE"] == "dark" ? .dark : .unspecified
            Self.keyWindow?.overrideUserInterfaceStyle = style
        }
        if let name = env["ANTCLOUD_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let window = Self.keyWindow else { return }
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? image.pngData()?.write(to: docs.appendingPathComponent("\(name).png"))
                Log.info("[preview] saved \(name).png")
            }
        }
        return true
        #else
        return false
        #endif
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }

    func start() {
        guard let profile = auth.profile else { return }
        Task { await session.startIfAllowed(settings: Self.moonlightStreamSettings(), nightPlan: profile.isNightPlan) }
    }

    /// Sets the cloud PC's display to match Moonlight's settings and returns its address.
    func prepareConnection() async throws -> String {
        let host = try await session.api.vmIP()
        session.applySettings(Self.moonlightStreamSettings())
        return host
    }

    private func submitPairingPIN(_ pin: String) async {
        Log.info("[panel] Moonlight is pairing, session phase \(session.phase)")
        guard session.phase != .idle else { return }
        _ = await session.submitPairingPIN(pin, attempts: 15)
    }

    /// Translates Moonlight's stream settings into the server's `stream` spec.
    static func moonlightStreamSettings() -> StreamSettings {
        var settings = StreamSettings()
        guard let moonlight = DataManager().getSettings() else { return settings }
        let width = moonlight.width.doubleValue
        let height = moonlight.height.doubleValue
        settings.resolution = ["720", "1080", "1440", "2160"]
            .min { abs(Double($0)! - height) < abs(Double($1)! - height) } ?? "1080"
        settings.fps = moonlight.framerate.stringValue
        settings.bitrate = moonlight.bitrate.stringValue
        let ratio = height > 0 ? width / height : 16.0 / 9.0
        settings.aspect = ratio >= 2.2 ? .ultrawide : ratio >= 1.7 ? .wide : .tall
        // `preferredCodec` is an anonymous C enum, which Swift doesn't import; 1 == CODEC_PREF_H264.
        settings.hevc = (moonlight.value(forKey: "preferredCodec") as? Int) != 1
        return settings
    }

    private static func presentOverMoonlight(_ notice: SessionService.Notice) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        let alert = UIAlertController(title: notice.title, message: notice.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        top?.present(alert, animated: true)
    }
}

struct AntCloudRootView: View {
    @ObservedObject var store: AntCloudStore
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        NavigationStack {
            ZStack {
                switch auth.state {
                case .restoring:
                    // The logo grows slightly and dissolves into the app, continuing the launch screen.
                    LaunchSplash()
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.12))))
                case .loggedOut:
                    // The aurora runs under a see-through bar on the sign-in screen.
                    LoginView()
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .transition(.opacity)
                case .loggedIn:
                    AntCloudHomeView(store: store)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: auth.state)
        }
        .tint(.antBlue)
    }
}

/// Continues the launch screen (same colour, same logo, same place) while the saved sign-in loads.
private struct LaunchSplash: View {
    var body: some View {
        ZStack {
            Color("AntCloudLaunchBackground").ignoresSafeArea()
            Image("AntCloudLaunchLogo")
                .resizable()
                .frame(width: 171, height: 171)
            ProgressView()
                .offset(y: 120)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
