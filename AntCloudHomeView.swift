import SwiftUI

/// AntCloud panel inside Moonlight: start the cloud PC, then Play hands off to Moonlight,
/// which adds, pairs (PIN submitted automatically) and launches "Desktop".
struct AntCloudHomeView: View {
    @ObservedObject var store: AntCloudStore
    @ObservedObject private var session: SessionService
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var connecting = false
    @State private var nightMonitorOff = SessionService.nightPlanMonitorDisabled

    init(store: AntCloudStore) {
        self.store = store
        _session = ObservedObject(wrappedValue: store.session)
    }

    var body: some View {
        Form {
            accountSection
            cloudPCSection
            streamSection
            developerSection
            appExpirySection
        }
        .navigationTitle("AntCloud")
        .toolbar { accountMenu }
        .refreshable { await auth.reloadProfile() }
        .onAppear { AppExpiry.scheduleReminder() }
        .alert(item: $session.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
    }

    // MARK: Sections

    private var accountSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hi, \(auth.profile?.firstName ?? "there")").font(.title2.bold())
                if let profile = auth.profile {
                    HStack(spacing: 12) {
                        Label(profile.currentPlan, systemImage: "creditcard")
                        if let minutes = profile.minutesLeft {
                            Label("\(minutes / 60)h \(minutes % 60)m", systemImage: "clock")
                        }
                        if let days = profile.daysLeft {
                            Label("Renews in \(days)d", systemImage: "calendar")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var cloudPCSection: some View {
        Section("Cloud PC") {
            HStack(spacing: 10) {
                if session.phase.isBusy || connecting { ProgressView() }
                Text(connecting ? "Connecting…" : session.phase.statusText).font(.headline)
            }
            switch session.phase {
            case .idle:
                Button("Start Cloud PC", action: startCloudPC).bold()
            case .ready, .pairing, .streaming:
                Button(action: play) {
                    Label("Play", systemImage: "play.fill").bold()
                }
                .disabled(connecting)
                Button("Shut Down", role: .destructive) { session.shutDown() }
            default:
                Button("Shut Down", role: .destructive) { session.shutDown() }
            }
        }
    }

    private var streamSection: some View {
        Section {
            LabeledContent("Stream", value: AntCloudStore.moonlightStreamSummary())
            Button("Open Moonlight") { dismiss() }
        } footer: {
            Text("Change resolution, frame rate and bitrate in Moonlight → Settings. Your cloud PC's display follows them when you press Play.")
        }
    }

    private var developerSection: some View {
        Section {
            Toggle("Disable night-plan auto-shutdown", isOn: $nightMonitorOff)
                .onChange(of: nightMonitorOff) { _, value in
                    SessionService.nightPlanMonitorDisabled = value
                }
        } header: {
            Text("Developer")
        } footer: {
            Text("Stops this app from ending a night-plan session at 9:35 AM IST. The AntCloud server still enforces night-plan hours on its side, so this only affects the local check — for testing the client.")
        }
    }

    private var appExpirySection: some View {
        Section {
            if let date = AppExpiry.date, let days = AppExpiry.daysLeft {
                LabeledContent("App expires") {
                    Text(date, format: .dateTime.day().month().hour().minute())
                        .foregroundStyle(days <= 1 ? .red : days <= 2 ? .orange : .secondary)
                }
                LabeledContent("Days left", value: days <= 0 ? "Less than a day" : "\(days)")
            } else {
                LabeledContent("App expires", value: "Unknown")
            }
        } header: {
            Text("This app")
        } footer: {
            Text("Free Apple ID builds stop opening after 7 days. You'll get a reminder the day before — then plug your iPhone into your Mac and reinstall.")
        }
    }

    private var accountMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Refresh account") { Task { await auth.reloadProfile() } }
                Button("Plans & pricing") { openURL(Config.pricingURL) }
                Button("Log out", role: .destructive) {
                    session.shutDown()
                    auth.logout()
                }
            } label: {
                Image(systemName: "person.crop.circle")
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
            } catch {
                Log.info("[panel] play failed: \(error.localizedDescription)")
                session.notice = .init(title: "Couldn't Connect", message: error.localizedDescription)
            }
        }
    }
}
