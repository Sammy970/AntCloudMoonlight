import Foundation
import SwiftUI

/// Notices when AntCloud changes its service under these apps.
///
/// AntCloud ships a Windows client and has renamed API routes alongside a new version (0.015 → 0.016
/// on 2026-10-30 renamed every route). So the app checks the published version on launch, and the API
/// client reports any route the server says no longer exists. Either one shows `UpstreamBanner`.
@MainActor
final class UpstreamStatus: ObservableObject {
    static let shared = UpstreamStatus()

    /// The Windows client version whose API routes these apps match (re/FINDINGS.md).
    /// Bump it after updating `APIClient` for a new AntCloud release.
    static let matchedClientVersion = 0.016

    /// AntCloud's current Windows client version, when it's newer than the one we match.
    @Published private(set) var newerClientVersion: Double?
    /// A request the server answered with "route doesn't exist", e.g. "POST phoneLogin".
    @Published private(set) var missingRoute: String?

    private static let dismissedKey = "dismissedUpstreamVersion"

    private init() {
        #if DEBUG
        // Screenshot mode: `ANTCLOUD_UPSTREAM=version:0.017` or `route:POST phoneLogin` shows the banner.
        if let value = ProcessInfo.processInfo.environment["ANTCLOUD_UPSTREAM"] {
            if value.hasPrefix("version:") { newerClientVersion = Double(value.dropFirst(8)) }
            if value.hasPrefix("route:") { missingRoute = String(value.dropFirst(6)) }
        }
        #endif
    }

    func check(api: APIClient) async {
        guard let latest = await api.windowsClientVersion() else { return }
        let dismissed = UserDefaults.standard.double(forKey: Self.dismissedKey)
        if latest > Self.matchedClientVersion + 0.0001, latest != dismissed {
            Log.info("[upstream] AntCloud's Windows client is \(latest); this app matches \(Self.matchedClientVersion)")
            newerClientVersion = latest
        }
    }

    func markRouteMissing(_ route: String) {
        missingRoute = route
    }

    /// Hides the version notice until AntCloud releases another one. A missing route stays visible.
    func dismissVersionNotice() {
        if let newerClientVersion { UserDefaults.standard.set(newerClientVersion, forKey: Self.dismissedKey) }
        newerClientVersion = nil
    }
}

/// Explains, in place, that AntCloud changed something and this app may need an update.
struct UpstreamBanner: View {
    @ObservedObject private var status = UpstreamStatus.shared

    var body: some View {
        if let route = status.missingRoute {
            banner(title: "AntCloud changed their service",
                   message: "Part of it this app uses (\(route)) no longer exists, so some things won't work until this app is updated.",
                   tint: .red, dismissible: false)
        } else if let version = status.newerClientVersion {
            banner(title: "AntCloud updated their app",
                   message: "Their Windows app is now version \(Self.format(version)); this app matches \(Self.format(UpstreamStatus.matchedClientVersion)). Past updates have changed sign-in and streaming, so if something stops working, this app needs updating.",
                   tint: .orange, dismissible: true)
        }
    }

    private func banner(title: String, message: String, tint: Color, dismissible: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if dismissible {
                Spacer(minLength: 0)
                Button {
                    withAnimation { status.dismissVersionNotice() }
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 16, tint: tint.opacity(0.12))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private static func format(_ version: Double) -> String {
        version.formatted(.number.precision(.fractionLength(3)))
    }
}
