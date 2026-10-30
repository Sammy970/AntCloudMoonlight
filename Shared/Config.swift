import Foundation

enum Config {
    static let apiBase = URL(string: "https://api.antcloud.co/api")!
    static let socketURL = URL(string: "https://socket.antcloud.co:8000")!
    static let origin = "https://antcloud.co"
    static let pricingURL = URL(string: "https://antcloud.co/pricing")!
    static let signupURL = URL(string: "https://antcloud.co/signup")!

    /// Value of the `connection` socket query param. The Windows client sends "Windows";
    /// the server may gate behaviour on it, so we keep that until a Mac value is known to work.
    static let connectionType = "Windows"

    /// Sunshine app name started on the VM.
    static let hostApp = "Desktop"

    /// UDP port on the VM that receives raw microphone PCM.
    static let micPort: UInt16 = 9002

    static let keychainService = "co.antcloud.mac"

    // MARK: Version

    /// This app's version: `0.<AntCloud release>.<our release>`. 0.16.x matches AntCloud's Windows app
    /// 0.016, whose API routes `APIClient` uses. Bump the middle number after updating `APIClient` for a new
    /// AntCloud release (0.17.0 for their 0.017), and the last one for our own changes. The build scripts
    /// stamp this into the app bundles, and the upstream check compares against it.
    static let appVersion = "0.16.0"

    /// The AntCloud Windows client version this build matches, read from `appVersion` (0.16.x → 0.016).
    static var matchedClientVersion: Double {
        let parts = appVersion.split(separator: ".")
        return parts.count > 1 ? (Double(parts[1]) ?? 0) / 1000 : 0
    }

    // MARK: Credits

    static let creatorName = "Samyak Jain"
    static let creatorGitHub = URL(string: "https://github.com/Sammy970")!
    static let creatorX = URL(string: "https://x.com/Sammy_970")!
    static let creatorAvatar = URL(string: "https://github.com/Sammy970.png?size=240")!
    static let moonlightURL = URL(string: "https://moonlight-stream.org")!
    #if os(iOS)
    static let appName = "AntCloud for iPhone"
    static let sourceURL = URL(string: "https://github.com/Sammy970/AntCloudMoonlight")!
    #else
    static let appName = "AntCloud for Mac"
    static let sourceURL = URL(string: "https://github.com/Sammy970/AntCloudMac")!
    #endif
}
