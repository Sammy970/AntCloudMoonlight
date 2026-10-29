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
}
