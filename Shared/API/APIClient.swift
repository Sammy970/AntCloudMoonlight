import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

struct UserProfile {
    let firstName: String
    let email: String
    let currentPlan: String
    let renewDate: Date?
    let totalTimeMonth: Int
    let timeUsedMonth: Int
    let preferredResolution: String?

    init(json: [String: Any]) {
        firstName = json["firstName"] as? String ?? "User"
        email = json["email"] as? String ?? ""
        currentPlan = json["currentPlan"] as? String ?? "basic"
        renewDate = (json["renewDate"] as? String).flatMap(UserProfile.parseDate)
        totalTimeMonth = json["totalTimeMonth"] as? Int ?? 0
        timeUsedMonth = json["timeUsedMonth"] as? Int ?? 0
        preferredResolution = json["resolution"].map { "\($0)" }
    }

    /// "basic" means no paid plan; the Windows client refuses to start a stream for it.
    var hasPaidPlan: Bool { currentPlan.caseInsensitiveCompare("basic") != .orderedSame }
    /// Night plans are identified by a plan code ending in "Nyt".
    var isNightPlan: Bool { currentPlan.lowercased().hasSuffix("nyt") }
    var minutesLeft: Int? { totalTimeMonth > 0 ? max(0, totalTimeMonth - timeUsedMonth) : nil }
    var daysLeft: Int? { renewDate.map { Calendar.current.dateComponents([.day], from: .now, to: $0).day ?? 0 } }

    private static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }
}

/// Thin client for https://api.antcloud.co/api. Responses are loosely shaped, so JSON is
/// handled as dictionaries rather than strict Codable models.
final class APIClient {
    var accessToken: String?
    /// Called once on a 401 to obtain a new access token; returns nil if refresh failed.
    var refreshHandler: (() async -> String?)?

    private let session = URLSession(configuration: .ephemeral)

    // MARK: Auth

    func login(email: String, password: String) async throws -> (access: String, refresh: String?) {
        let json = try await send("POST", "users/login", body: ["email": email, "password": password])
        return try Self.tokens(from: json)
    }

    func sendOTP(phone: String) async throws {
        _ = try await send("POST", "phone/otp", body: ["phone": phone, "signup": false])
    }

    func phoneLogin(phone: String, otp: String) async throws -> (access: String, refresh: String?) {
        let json = try await send("POST", "users/phone/login", body: ["phone": phone, "_verificationToken": otp])
        return try Self.tokens(from: json)
    }

    func forgotPassword(email: String) async throws {
        _ = try await send("POST", "users/forgot-password", body: ["email": email])
    }

    func refresh(refreshToken: String) async throws -> (access: String, refresh: String?) {
        let json = try await send("GET", "users/refresh", headers: ["refresh": "JWT \(refreshToken)"]) as? [String: Any]
        guard let access = json?["accessToken"] as? String, !access.isEmpty else {
            throw APIError(status: 0, message: "Session expired. Please log in again.")
        }
        return (access, json?["refreshToken"] as? String)
    }

    func me() async throws -> UserProfile {
        let json = try await send("GET", "users/me", authorized: true) as? [String: Any]
        guard let user = json?["user"] as? [String: Any] else {
            throw APIError(status: 0, message: "Unexpected profile response.")
        }
        return UserProfile(json: user)
    }

    // MARK: VM

    func vmIP() async throws -> String {
        let json = try await send("GET", "vm/getVmIp", authorized: true) as? [String: Any]
        guard let ip = json?["vmip"] as? String, !ip.isEmpty else {
            throw APIError(status: 0, message: "VM IP not available yet.")
        }
        return ip
    }

    /// Hands the Moonlight pairing PIN to the backend, which enters it into Sunshine on the VM.
    func vmAuth(pin: String) async throws -> Bool {
        let json = try await send("POST", "vm/vmauth", body: ["pin": pin], authorized: true)
        if let ok = json as? Bool { return ok }
        if let dict = json as? [String: Any] {
            // Current server shape: {"message":"success","data":{"status":true|false}}
            if let ok = (dict["data"] as? [String: Any])?["status"] as? Bool { return ok }
            for key in ["success", "accepted", "result", "ok"] {
                if let ok = dict[key] as? Bool { return ok }
            }
        }
        return false
    }

    func connectionStatus() async throws -> Bool {
        let json = try await send("GET", "vm/checkconnectionstatus", authorized: true) as? [String: Any]
        return json?["connected"] as? Bool ?? false
    }

    /// Server clock (IST), used for night-plan windows.
    func serverTime() async -> Date? {
        guard let json = try? await send("GET", "realtime") as? [String: Any],
              let s = json["time"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    // MARK: Transport

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil,
                      headers: [String: String] = [:], authorized: Bool = false,
                      isRetry: Bool = false) async throws -> Any? {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 30
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if authorized, let token = accessToken {
            req.setValue("JWT \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        // Poll endpoints are logged only when something is off; auth bodies are never logged.
        // checkconnectionstatus answers 400 {"connected":false} until Moonlight connects — expected, so not logged.
        if path != "vm/checkconnectionstatus" {
            let preview = path.hasPrefix("users/") || path.hasPrefix("phone/") ? "" : " " + String(decoding: data.prefix(300), as: UTF8.self)
            Log.info("[api] \(method) \(path) → \(status)\(preview)")
        }

        if status == 401, authorized, !isRetry, let refreshHandler, let fresh = await refreshHandler() {
            accessToken = fresh
            return try await send(method, path, body: body, headers: headers, authorized: true, isRetry: true)
        }
        guard (200..<300).contains(status) else {
            throw APIError(status: status, message: Self.errorMessage(from: json) ?? "Request failed (\(status)).")
        }
        return json
    }

    private static func tokens(from json: Any?) throws -> (access: String, refresh: String?) {
        let root = json as? [String: Any] ?? [:]
        let user = root["user"] as? [String: Any] ?? [:]
        guard let access = (root["token"] ?? user["token"]) as? String else {
            throw APIError(status: 0, message: "Login response did not include a token.")
        }
        return (access, (root["refreshToken"] ?? user["refreshToken"]) as? String)
    }

    private static func errorMessage(from json: Any?) -> String? {
        guard let dict = json as? [String: Any] else { return nil }
        if let errors = dict["errors"] as? [[String: Any]] {
            let messages = errors.compactMap { $0["message"] as? String }
            if !messages.isEmpty { return messages.joined(separator: "\n") }
        }
        return (dict["error"] as? String) ?? (dict["message"] as? String)
    }
}
