import Foundation
import SocketIO

/// Platform-specific part of a launch: pairing with and streaming from the VM's Sunshine host.
/// macOS drives the Moonlight app's CLI; iOS has no driver (the user runs Moonlight themselves).
@MainActor
protocol StreamDriver: AnyObject {
    /// Pairs if needed and streams until the stream ends. Call `session.markStreaming()`
    /// once pairing is done and `session.markPairing()` if it has to pair again.
    func run(host: String, settings: StreamSettings, session: SessionService) async throws
    /// Stops anything `run` started. Called when the session tears down.
    func stop()
}

/// Owns one cloud-PC session: the Socket.IO connection that allocates/boots the VM,
/// VM readiness, server notices, and (with a `StreamDriver`) the running stream.
@MainActor
final class SessionService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        case queued(position: Int?)
        case booting
        case ready
        case pairing
        case streaming

        var statusText: String {
            switch self {
            case .idle: "Your cloud PC is off"
            case .connecting: "Connecting to AntCloud…"
            case .queued(let position): position.map { "In queue — position \($0)" } ?? "Waiting for a server…"
            case .booting: "Starting your cloud PC…"
            case .ready: "Cloud PC is ready"
            case .pairing: "Pairing with your cloud PC…"
            case .streaming: "Streaming"
            }
        }

        var isBusy: Bool {
            switch self {
            case .connecting, .queued, .booting, .pairing: true
            default: false
            }
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published private(set) var phase: Phase = .idle
    @Published var notice: Notice?

    /// Fired when the server says the token is no longer valid.
    var onSessionExpired: (() -> Void)?

    let api: APIClient
    private let driver: StreamDriver?
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var intentionalDisconnect = false
    private var vmWaitTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
    private var nightPlanTask: Task<Void, Never>?

    init(api: APIClient, driver: StreamDriver? = nil) {
        self.api = api
        self.driver = driver
    }

    var isActive: Bool { phase != .idle }

    #if DEBUG
    /// Screenshot mode: forces a phase without opening a session.
    func previewPhase(_ phase: Phase) { self.phase = phase }
    #endif

    // MARK: Session lifecycle

    /// Starts a session, but tells a night-plan user up front when it's outside the plan's hours,
    /// instead of booting the PC only for the server to refuse it later.
    func startIfAllowed(settings: StreamSettings, nightPlan: Bool) async {
        guard phase == .idle else { return }
        if nightPlan && !Self.nightPlanMonitorDisabled {
            let now = await api.serverTime() ?? .now
            guard Self.isNightPlanWindow(now) else {
                Log.info("[session] night plan outside its hours; not starting")
                notice = Notice(title: "Night Plan Hours",
                                message: "Your night plan works between 12:30 AM and 9:30 AM IST. Come back then, or switch plans for daytime play.")
                return
            }
        }
        start(settings: settings, nightPlan: nightPlan)
    }

    /// Night plans can start between 12:30 AM and 9:30 AM IST.
    static func isNightPlanWindow(_ date: Date) -> Bool {
        var ist = Calendar(identifier: .gregorian)
        ist.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let parts = ist.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes >= 30 && minutes < 9 * 60 + 30
    }

    func start(settings: StreamSettings, nightPlan: Bool) {
        guard phase == .idle, let token = api.accessToken else { return }
        intentionalDisconnect = false
        phase = .connecting
        Log.info("[session] connecting, stream spec \"\(settings.serverSpec)\", night plan \(nightPlan)")

        let manager = SocketManager(socketURL: Config.socketURL, config: [
            .path("/socket.io/"),
            .forceWebsockets(true),
            .reconnects(false),
            .extraHeaders(["Origin": Config.origin]),
            .connectParams([
                "type": "client",
                "game": "desktop",
                "token": token,
                "stream": settings.serverSpec,
                "connection": Config.connectionType,
            ]),
        ])
        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket

        socket.on("status") { [weak self] data, _ in
            guard let status = (data.first as? String)?.lowercased().trimmingCharacters(in: .whitespaces) else { return }
            if status.hasPrefix("waiting") {
                let position = status.split(separator: " ").dropFirst().first.flatMap { Int($0) }
                self?.phase = .queued(position: position)
            } else if status == "starting" {
                self?.phase = .booting
            }
        }

        socket.onAny { event in
            Log.info("[socket] event \(event.event) → \(event.items ?? [])")
        }

        socket.on(clientEvent: .connect) { _, _ in
            Log.info("[socket] connected")
        }

        socket.on("new_connection") { [weak self] data, _ in
            let clients = (data.first as? [String: Any])?["clients"] as? Int ?? 0
            if clients >= 2 { self?.vmJoined(nightPlan: nightPlan) }
        }

        socket.on("inactive") { [weak self] data, _ in
            self?.handleInactive(data.first as? String ?? "unknown")
        }

        socket.on("reset") { [weak self] _, _ in
            self?.vmWaitTask?.cancel()
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            guard let self else { return }
            Log.info("[socket] disconnected: \(data.first ?? "unknown") (intentional: \(intentionalDisconnect))")
            let wasIntentional = intentionalDisconnect
            teardown()
            if !wasIntentional {
                notice = Notice(title: "Disconnected", message: "Lost connection to the AntCloud server (\(data.first as? String ?? "unknown")).")
            }
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            guard let self, phase == .connecting else { return }
            teardown()
            notice = Notice(title: "Connection Error", message: "Could not reach the stream server: \(data.first ?? "unknown error")")
        }

        socket.connect()
    }

    /// Ends the session and shuts down the VM.
    func shutDown() {
        guard let socket else { teardown(); return }
        intentionalDisconnect = true
        socket.emit("closestream")
        socket.disconnect()
        teardown()
    }

    /// Pushes new display settings to the VM (the server reconfigures the host resolution).
    func applySettings(_ settings: StreamSettings) {
        socket?.emit("setstream", settings.serverSpec)
    }

    // MARK: Streaming

    /// Fetches the VM address, applies display settings and hands off to the platform driver.
    func launchStream(settings: StreamSettings) {
        guard phase == .ready, let driver else { return }
        phase = .pairing
        launchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let host = try await api.vmIP()
                applySettings(settings)
                try await driver.run(host: host, settings: settings, session: self)
            } catch is CancellationError {
            } catch {
                notice = Notice(title: "Stream Error", message: error.localizedDescription)
            }
            if phase == .pairing || phase == .streaming { phase = .ready }
        }
    }

    func markStreaming() {
        if phase == .pairing { phase = .streaming }
    }

    func markPairing() {
        if phase == .streaming { phase = .pairing }
    }

    /// Hands a Moonlight pairing PIN to the backend, which enters it into Sunshine on the VM.
    /// Retries for a while because Sunshine only accepts it once Moonlight's pair request has arrived.
    func submitPairingPIN(_ pin: String, attempts: Int = 10) async -> Bool {
        for attempt in 1...attempts {
            if (try? await api.vmAuth(pin: pin)) == true {
                Log.info("[pair] PIN accepted on attempt \(attempt)")
                return true
            }
            guard attempt < attempts, (try? await Task.sleep(for: .seconds(2))) != nil else { break }
        }
        Log.info("[pair] PIN not accepted after \(attempts) attempts")
        return false
    }

    // MARK: VM readiness

    /// The VM agent joined the room. Like the Windows client, the stream can be launched right away;
    /// `/vm/checkconnectionstatus` only turns true once Moonlight has connected, at which point the
    /// server is told to start video.
    private func vmJoined(nightPlan: Bool) {
        if phase != .pairing && phase != .streaming { phase = .ready }
        guard vmWaitTask == nil else { return }
        vmWaitTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let connected = (try? await api.connectionStatus()) == true
                if connected { break }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, let socket, socket.status == .connected else { return }
            Log.info("[session] VM reports connected → control video")
            socket.emit("control", "video")
            if nightPlan { startNightPlanMonitor() }
        }
    }

    /// When true, the client-side night-plan monitor is disabled (for testing). This does NOT
    /// affect the server's own enforcement of night-plan hours; it only stops our local 9:35 check.
    static var nightPlanMonitorDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: "nightPlanMonitorDisabled") }
        set { UserDefaults.standard.set(newValue, forKey: "nightPlanMonitorDisabled") }
    }

    /// Night plans are only valid 00:30–09:35 IST; end the session once the server clock passes the cutoff.
    private func startNightPlanMonitor() {
        if Self.nightPlanMonitorDisabled {
            Log.info("[session] night-plan monitor disabled by setting; not starting")
            return
        }
        nightPlanTask?.cancel()
        nightPlanTask = Task { [weak self] in
            var ist = Calendar(identifier: .gregorian)
            ist.timeZone = TimeZone(identifier: "Asia/Kolkata")!
            while !Task.isCancelled {
                guard let self else { return }
                let now = await api.serverTime() ?? .now
                let parts = ist.dateComponents([.hour, .minute], from: now)
                if (parts.hour ?? 0) * 60 + (parts.minute ?? 0) >= 9 * 60 + 35 {
                    shutDown()
                    notice = Notice(title: "Night Plan Ended", message: "Your night plan session ended at 9:30 AM IST. The next window opens at 12:30 AM IST.")
                    return
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: Server notices

    private func handleInactive(_ reason: String) {
        let messages: [String: (String, String)] = [
            "daytime": ("Night Plan", "Outside active hours. Come back between 12:30 AM and 9:30 AM."),
            "emailverification": ("Email Verification Required", "Please verify your email address to continue using AntCloud. Check your inbox for the verification link."),
            "dual": ("Multiple Connections Detected", "Another stream is already running on this account. Close the other connection and try again."),
            "inactive": ("Account Disabled", "Your account has been disabled. Contact support@antcloud.co for assistance."),
            "vmnotfound": ("Profile Not Ready", "Your streaming profile is still being prepared. Please wait 5 minutes and try again."),
            "vmissue": ("Virtual Machine Error", "Failed to launch your virtual machine. Please wait 2–3 minutes and try again."),
            "serversfull": ("Servers at Capacity", "All servers are currently busy. Please wait 5–10 minutes and try again."),
            "wrongToken": ("Session Expired", "Your session has expired. Please log in again."),
            "planendwarning": ("Plan Expiring Soon", "Your plan will expire soon. Renew to avoid interruption."),
            "planover": ("Plan Expired", "Your plan has expired. Renew to continue using AntCloud."),
        ]

        if reason == "videonotstarting" {
            shutDown()
            notice = Notice(title: "Stream Failed", message: "The VM's video did not start. Please try again.")
            return
        }

        let (title, message) = messages[reason] ?? ("Connection Error", "An unexpected error occurred: \(reason)")
        notice = Notice(title: title, message: message)

        switch reason {
        case "wrongToken", "inactive":
            shutDown()
            onSessionExpired?()
        case "planover":
            shutDown()
        default:
            break
        }
    }

    private func teardown() {
        if phase != .idle { Log.info("[session] teardown from \(phase)") }
        vmWaitTask?.cancel()
        vmWaitTask = nil
        launchTask?.cancel()
        nightPlanTask?.cancel()
        driver?.stop()
        socket?.removeAllHandlers()
        socket = nil
        manager = nil
        phase = .idle
    }
}
