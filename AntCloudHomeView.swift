import SwiftUI

/// AntCloud home: start the cloud PC, then Play hands off to Moonlight,
/// which adds, pairs (PIN submitted automatically) and launches "Desktop".
struct AntCloudHomeView: View {
    @ObservedObject var store: AntCloudStore
    @ObservedObject private var session: SessionService
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var connecting = false
    @State private var nightMonitorOff = SessionService.nightPlanMonitorDisabled
    @State private var prefs = MoonlightPrefs.load()
    @State private var showingSettings = false
    @State private var showingNetwork = false
    @State private var showingAbout = false
    @State private var showingControllers = false
    /// Watches controllers for the controller-check card and sheet.
    @StateObject private var gamepads = GamepadMonitor()
    /// Kept here so the card can show the last result.
    @StateObject private var networkCheck = NetworkCheck()

    init(store: AntCloudStore) {
        self.store = store
        _session = ObservedObject(wrappedValue: store.session)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                UpstreamBanner()
                    .padding(.bottom, 14)

                header
                    .reveal(0)
                    .padding(.bottom, 20)

                DisplayHero(phase: session.phase)
                    .frame(maxWidth: 290)
                    .reveal(0.06)
                    .padding(.bottom, 26)

                VStack(spacing: 6) {
                    Text(connecting ? "Connecting to your cloud PC…" : session.phase.statusText)
                        .font(.title3.weight(.semibold))
                    Text(connecting ? "Your stream opens in a moment." : detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .id(connecting ? "connecting" : session.phase.screenState)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .reveal(0.12)
                .padding(.bottom, 20)

                ConnectionTrack(phase: session.phase)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .glassSurface(cornerRadius: 26)
                    .reveal(0.18)
                    .padding(.bottom, 24)

                actions
                    .reveal(0.24)
                    .padding(.bottom, 28)

                GlassGroup(spacing: 14) {
                    VStack(spacing: 14) {
                        streamCard.reveal(0.3)
                        networkCard.reveal(0.33)
                        controllerCard.reveal(0.345)
                        appCard.reveal(0.36)
                    }
                }

                Button { showingAbout = true } label: {
                    HStack(spacing: 6) {
                        Text("\(Config.appName) \(Config.appVersion)")
                        Text("·")
                        Text("Made by \(Config.creatorName)").fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .glassCapsule()
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
                .reveal(0.42)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            // Exactly the screen's width, so nothing can push the page sideways.
            .containerRelativeFrame(.horizontal)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: session.phase)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background { AuroraBackground(intensity: 0.5) }
        .navigationTitle("AntCloud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { accountMenu }
        .refreshable { await auth.reloadProfile() }
        .onAppear { AppExpiry.scheduleReminder() }
        .sensoryFeedback(trigger: session.phase) { old, new in
            switch new {
            case .ready, .streaming: .success
            case .idle where old != .idle: .impact(weight: .light)
            default: nil
            }
        }
        .sensoryFeedback(.warning, trigger: session.notice?.id)
        .sensoryFeedback(.selection, trigger: prefs)
        .sheet(isPresented: $showingSettings) {
            StreamSettingsSheet(prefs: $prefs)
        }
        .sheet(isPresented: $showingAbout) {
            NavigationStack {
                ScrollView { AboutView() }
                    .background { AuroraBackground(intensity: 0.35) }
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingAbout = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingNetwork) {
            NavigationStack {
                NetworkCheckView(
                    check: networkCheck,
                    resolution: String(prefs.height),
                    fps: String(prefs.fps),
                    bitrate: prefs.bitrateKbps,
                    applyBitrate: { prefs.bitrateKbps = $0; prefs.save() },
                    busy: connecting || session.phase == .pairing
                )
                .background { AuroraBackground(intensity: 0.35) }
                .navigationTitle("Network Check")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingNetwork = false }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: networkCheck.stage == .done)
        }
        .sheet(isPresented: $showingControllers) {
            ControllersSheet(monitor: gamepads) { showingControllers = false }
        }
        .onAppear(perform: previewControllers)
        .alert(item: $session.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
    }

    /// On iPhone Moonlight streams on its own, so "ready" means "tap Play".
    private var detailText: String {
        session.phase == .ready ? "Tap Play. It connects and pairs on its own." : session.phase.detailText
    }

    // MARK: Header

    /// Who's signed in and how much plan time is left: the first thing to see.
    @ViewBuilder
    private var header: some View {
        if let profile = auth.profile {
            card {
                VStack(alignment: .leading, spacing: 14) {
                    ProfileBadge(profile: profile, size: 40)
                    PlanUsage(profile: profile)
                }
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch session.phase {
            case .idle:
                primary("Start Cloud PC", systemImage: "power", action: startCloudPC)
            case .ready, .pairing, .streaming:
                primary(connecting ? "Connecting" : "Play", systemImage: "play.fill", action: play)
                    .disabled(connecting)
                shutDown
            default:
                shutDown
            }
        }
    }

    private func primary(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if connecting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: systemImage).contentTransition(.symbolEffect(.replace))
                }
                Text(title).contentTransition(.interpolate)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .primaryGlassButton()
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private var shutDown: some View {
        Button(role: .destructive) { session.shutDown() } label: {
            Text(session.phase.isBusy ? "Cancel" : "Shut Down")
                .font(.body.weight(.medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .secondaryGlassButton()
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    // MARK: Cards

    private var streamCard: some View {
        Button { showingSettings = true } label: {
            card {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.antBlue.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stream settings").font(.subheadline.weight(.semibold))
                        Text(prefs.summary)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(connecting)
    }

    private var networkCard: some View {
        Button { showingNetwork = true } label: {
            card {
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(networkTint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Network check").font(.subheadline.weight(.semibold))
                        Text(networkSummary)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var controllerCard: some View {
        Button { showingControllers = true } label: {
            card {
                HStack(spacing: 12) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background((gamepads.pads.isEmpty ? Color.antBlue : .green).gradient,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Controller check").font(.subheadline.weight(.semibold))
                        Text(gamepads.pads.first.map { "\($0.name) · Ready to play" } ?? "Check a controller's buttons and sticks before you play")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Debug builds only: `ANTCLOUD_PREVIEW=home:<phase>:controllers` opens the controller check, and
    /// `:sample` shows a sample controller mid-press.
    private func previewControllers() {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["ANTCLOUD_PREVIEW"] else { return }
        if value.contains(":sample") { gamepads.showPreview() }
        if value.contains(":controllers") { showingControllers = true }
        #endif
    }

    /// The last result, e.g. "45 ms · Good · 322 Mbps", or what the check does.
    private var networkSummary: String {
        guard let median = networkCheck.medianLatency, networkCheck.stage == .done else {
            return networkCheck.isRunning ? "Testing…" : "See how a stream would feel, before starting your PC"
        }
        let zone = LatencyScale.zone(for: median).name
        let speed = networkCheck.downloadMbps.map { " · \(Int($0.rounded())) Mbps" } ?? ""
        return "\(Int(median.rounded())) ms · \(zone)\(speed)"
    }

    private var networkTint: Color {
        guard let median = networkCheck.medianLatency, networkCheck.stage == .done else { return .antBlue }
        return LatencyScale.zone(for: median).color
    }

    private var appCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("This app", systemImage: "iphone").font(.subheadline.weight(.semibold))
                    Spacer()
                    expiry
                }
                Text("Free Apple ID builds stop opening after 7 days. You'll get a reminder the day before; then reinstall from your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(isOn: $nightMonitorOff) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip night-plan checks").font(.subheadline)
                        Text("For testing. Skips the app's own hours check and 9:35 AM IST cutoff; AntCloud still enforces plan hours on its servers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: nightMonitorOff) { _, value in
                    SessionService.nightPlanMonitorDisabled = value
                }
            }
        }
    }

    @ViewBuilder
    private var expiry: some View {
        if let date = AppExpiry.date, let days = AppExpiry.daysLeft {
            Text("Expires \(date.formatted(.dateTime.day().month().hour().minute()))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(days <= 1 ? .red : days <= 2 ? .orange : .secondary)
        } else {
            Text("Expiry unknown").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassSurface(cornerRadius: 26)
    }

    private var accountMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let email = auth.profile?.email { Text(email) }
                Button("Refresh Account", systemImage: "arrow.clockwise") { Task { await auth.reloadProfile() } }
                Button("Plans & Pricing", systemImage: "creditcard") { openURL(Config.pricingURL) }
                Button("About", systemImage: "info.circle") { showingAbout = true }
                Divider()
                Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    session.shutDown()
                    auth.logout()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: Actions

    private func startCloudPC() {
        guard let profile = auth.profile, profile.hasPaidPlan else {
            session.notice = .init(title: "Plan Required", message: "Please buy a plan to continue.")
            openURL(Config.pricingURL)
            return
        }
        store.start()
    }

    private func play() {
        connecting = true
        Task {
            defer { connecting = false }
            do {
                let host = try await store.prepareConnection()
                Log.info("[panel] play → \(host), phase \(session.phase)")
                // Moonlight's main screen picks this up in viewDidAppear once the panel is gone.
                AntCloudPanel.pendingConnectAddress = host
                dismiss()
                // The in-stream overlay (time left, health warnings) appears once the panel is gone.
                let profile = auth.profile
                Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    StreamOverlayWindow.shared.begin(host: host, profile: profile)
                }
            } catch {
                Log.info("[panel] play failed: \(error.localizedDescription)")
                session.notice = .init(title: "Couldn't Connect", message: error.localizedDescription)
            }
        }
    }
}
