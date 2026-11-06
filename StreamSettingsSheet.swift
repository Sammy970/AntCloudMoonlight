import SwiftUI

/// The Moonlight settings AntCloud exposes. Moonlight keeps them in its own database and reads
/// them when it connects, so editing them here is all it takes.
struct MoonlightPrefs: Equatable {
    var height = 1080
    /// The cloud PC's display shape. Stored in Moonlight as the width it streams at; `AntCloudPanel` reads it back
    /// from that width to tell the cloud PC which shape to use.
    var aspect = AspectRatio.wide
    var fps = 60
    var bitrateKbps = 20000
    var hevc = true
    var directTouch = false
    var onscreenControls = 1
    var statsOverlay = false
    var audioOnPC = false
    /// Fill the whole screen, stretching the picture (no black bars). Read by Moonlight's video and touch code.
    var stretchToFill = false

    static let stretchKey = "AntCloudStretchToFill"

    static let heights = [720, 1080, 1440, 2160]
    static let bitrates = [5000, 10000, 15000, 20000, 30000, 40000, 50000]

    var width: Int { aspect.width(height: height) }

    static func load() -> MoonlightPrefs {
        var prefs = MoonlightPrefs()
        guard let s = DataManager().getSettings() else { return prefs }
        let height = s.height.intValue
        prefs.height = heights.min { abs($0 - height) < abs($1 - height) } ?? 1080
        // Same thresholds as `AntCloudPanel.moonlightStreamSettings`, so the two always agree.
        let ratio = height > 0 ? s.width.doubleValue / Double(height) : 16.0 / 9.0
        prefs.aspect = ratio >= 2.2 ? .ultrawide : ratio >= 1.7 ? .wide : .tall
        prefs.fps = s.framerate.intValue
        prefs.bitrateKbps = s.bitrate.intValue
        // `preferredCodec` is an anonymous C enum Swift doesn't import; 1 == CODEC_PREF_H264.
        prefs.hevc = (s.value(forKey: "preferredCodec") as? Int) != 1
        prefs.directTouch = s.absoluteTouchMode
        prefs.onscreenControls = s.onscreenControls.intValue
        prefs.statsOverlay = s.statsOverlay
        prefs.audioOnPC = s.playAudioOnPC
        prefs.stretchToFill = UserDefaults.standard.bool(forKey: stretchKey)
        return prefs
    }

    /// Writes these values and keeps every other Moonlight setting as it was.
    func save() {
        UserDefaults.standard.set(stretchToFill, forKey: Self.stretchKey)
        let data = DataManager()
        guard let s = data.getSettings() else { return }
        data.saveSettings(
            withBitrate: bitrateKbps,
            framerate: fps,
            height: height,
            width: width,
            audioConfig: s.audioConfig.intValue,
            onscreenControls: onscreenControls,
            optimizeGames: s.optimizeGames,
            multiController: s.multiController,
            swapABXYButtons: s.swapABXYButtons,
            audioOnPC: audioOnPC,
            preferredCodec: hevc ? 2 : 1,
            useFramePacing: s.useFramePacing,
            enableHdr: s.enableHdr,
            btMouseSupport: s.btMouseSupport,
            absoluteTouchMode: directTouch,
            statsOverlay: statsOverlay
        )
    }

    /// e.g. "1080p · 60 FPS · 20 Mbps · HEVC"
    var summary: String {
        let res = height == 2160 ? "4K" : "\(height)p"
        let shape = aspect == .wide ? "" : " \(aspect.rawValue)"
        return "\(res)\(shape) · \(fps) FPS · \(bitrateKbps / 1000) Mbps · \(hevc ? "HEVC" : "H.264")"
    }

    var gigabytesPerHour: String {
        (Double(bitrateKbps) * 1000 * 3600 / 8 / 1e9).formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension AspectRatio {
    /// The width Moonlight streams at for a height, the same sizes the Mac and Windows clients use.
    func width(height: Int) -> Int {
        switch self {
        case .wide: height * 16 / 9
        case .tall: height * 16 / 10
        case .ultrawide: [720: 1680, 1080: 2560, 1440: 3440, 2160: 5120][height] ?? height * 64 / 27
        }
    }
}

/// Stream settings, edited in AntCloud and saved straight into Moonlight.
struct StreamSettingsSheet: View {
    @Binding var prefs: MoonlightPrefs
    /// 16:10 and 21:9 only work on Windows 11 cloud PCs (AntCloud's own app offers them only there); a Windows 10
    /// one keeps a 16:9 display and the stream gets black bars at the sides.
    var otherShapesAllowed: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Resolution", selection: $prefs.height) {
                        ForEach(MoonlightPrefs.heights, id: \.self) { Text($0 == 2160 ? "4K" : "\($0)p").tag($0) }
                    }
                    Picker("Frame rate", selection: $prefs.fps) {
                        Text("30").tag(30)
                        Text("60").tag(60)
                        Text("120").tag(120)
                    }
                    .pickerStyle(.segmented)
                    if otherShapesAllowed {
                        Picker("Aspect ratio", selection: $prefs.aspect) {
                            ForEach(AspectRatio.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Bitrate", selection: $prefs.bitrateKbps) {
                        ForEach(bitrateOptions, id: \.self) { Text("\($0 / 1000) Mbps").tag($0) }
                    }
                } header: {
                    Text("Picture")
                } footer: {
                    Text("Streams at \(prefs.width) × \(prefs.height) and uses up to \(prefs.gigabytesPerHour) GB of data per hour. Lower the bitrate if the picture stutters. " + shapeNote)
                }

                Section {
                    Toggle(isOn: $prefs.stretchToFill) {
                        Text("Stretch to fill screen")
                        Text("Removes the black bars at the sides. The picture looks a little wider than it is.")
                    }
                }

                Section {
                    Toggle(isOn: $prefs.hevc) {
                        Text("HEVC (H.265)")
                        Text("Sharper picture at the same bitrate.")
                    }
                }

                Section {
                    Toggle("Show performance stats", isOn: $prefs.statsOverlay)
                    Toggle(isOn: $prefs.audioOnPC) {
                        Text("Play sound on the cloud PC")
                        Text("Off sends the sound to your iPhone.")
                    }
                }
            }
            .navigationTitle("Stream Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: prefs) { _, value in value.save() }
    }

    private var shapeNote: String {
        otherShapesAllowed
            ? "21:9 fills more of an iPhone screen in landscape; 16:9 leaves bars at the sides but every game supports it."
            : "16:10 and 21:9 need a Windows 11 cloud PC. Yours runs Windows 10, so it streams at 16:9; turn on Stretch to fill to remove the bars."
    }

    /// The standard steps, plus the current value if Moonlight had a custom one.
    private var bitrateOptions: [Int] {
        MoonlightPrefs.bitrates.contains(prefs.bitrateKbps)
            ? MoonlightPrefs.bitrates
            : (MoonlightPrefs.bitrates + [prefs.bitrateKbps]).sorted()
    }
}

/// Touch, on-screen controls and the controller check, kept apart from the stream's picture settings.
struct ControlsSheet: View {
    @Binding var prefs: MoonlightPrefs
    @ObservedObject var monitor: GamepadMonitor
    @Environment(\.dismiss) private var dismiss
    /// Floating sticks and fade live in the on-screen layout, not in Moonlight's settings.
    @State private var floatingSticks = false
    @State private var fadeAfter = 0.0
    @State private var loaded = false
    @State private var showingControllers = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Level", selection: $prefs.onscreenControls) {
                        Text("Off").tag(0)
                        Text("Auto").tag(1)
                        Text("Simple").tag(2)
                        Text("Full").tag(3)
                    }
                    Toggle(isOn: $floatingSticks) {
                        Text("Floating sticks")
                        Text("Touch anywhere on the left or right half of the screen and a stick appears under your finger. The fixed sticks are hidden.")
                    }
                    Picker("Fade controls when idle", selection: $fadeAfter) {
                        ForEach(OSCLayout.fadeChoices, id: \.self) { Text($0 == 0 ? "Off" : "\(Int($0)) s").tag($0) }
                    }
                    Button {
                        AntCloudPanel.presentControlsEditor()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Customize layout")
                                Text("Move, resize or remove each control, and set how see-through they are.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("On-screen controls")
                } footer: {
                    Text("Auto shows the full controls when no controller is connected, and only the buttons a connected controller lacks (nothing if it has them all). Off hides them; Simple and Full always show them, Simple with fewer buttons.")
                }

                Section {
                    Picker("Touch", selection: $prefs.directTouch) {
                        Text("Trackpad").tag(false)
                        Text("Direct touch").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Touch")
                } footer: {
                    Text("Trackpad moves a cursor like a laptop trackpad. Direct touch clicks where your finger lands.")
                }

                Section {
                    Button {
                        showingControllers = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Check a controller")
                                Text(monitor.pads.first?.name ?? "Check a controller's buttons and sticks before you play")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Controller")
                }
            }
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            let layout = OSCLayoutStore.load()
            floatingSticks = layout.floatingSticks
            fadeAfter = layout.fadeAfter
            loaded = true
        }
        .onChange(of: floatingSticks) { _, _ in saveLayout() }
        .onChange(of: fadeAfter) { _, _ in saveLayout() }
        .onChange(of: prefs) { _, value in value.save() }
        .sheet(isPresented: $showingControllers) {
            ControllersSheet(monitor: monitor) { showingControllers = false }
        }
    }

    /// Re-loads first so the editor's positions and opacity are never overwritten with stale ones.
    private func saveLayout() {
        guard loaded else { return }
        var layout = OSCLayoutStore.load()
        layout.floatingSticks = floatingSticks
        layout.fadeAfter = fadeAfter
        OSCLayoutStore.save(layout)
    }
}
