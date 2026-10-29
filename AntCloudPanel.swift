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
    var panelVisible = false
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
        Task { await auth.restore() }
    }

    func start() {
        guard let profile = auth.profile else { return }
        session.start(settings: Self.moonlightStreamSettings(), nightPlan: profile.isNightPlan)
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

    /// e.g. "1280×720 · 60 FPS · 10 Mbps"
    static func moonlightStreamSummary() -> String {
        guard let moonlight = DataManager().getSettings() else { return "Default" }
        return "\(moonlight.width.intValue)×\(moonlight.height.intValue) · \(moonlight.framerate.intValue) FPS · \(moonlight.bitrate.intValue / 1000) Mbps"
    }
}

struct AntCloudRootView: View {
    @ObservedObject var store: AntCloudStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch auth.state {
                case .restoring:
                    ProgressView("Signing in…")
                case .loggedOut:
                    LoginView()
                case .loggedIn:
                    AntCloudHomeView(store: store)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Moonlight") { dismiss() }
                }
            }
        }
    }
}
