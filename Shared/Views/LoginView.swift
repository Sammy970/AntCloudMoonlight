import SwiftUI

struct LoginView: View {
    private enum Method: String, CaseIterable { case email = "Email", phone = "Phone" }

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL

    @State private var method = Method.email
    @State private var email = ""
    @State private var password = ""
    @State private var phone = ""
    @State private var otp = ""
    @State private var otpSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("AntCloud").font(.largeTitle.bold())
            Text("Sign in to your cloud PC").foregroundStyle(.secondary)

            Picker("", selection: $method) {
                ForEach(Method.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch method {
                case .email: emailForm
                case .phone: phoneForm
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(busy)

            if let error { Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
            if let info { Text(info).foregroundStyle(.secondary).font(.callout).multilineTextAlignment(.center) }
            if busy { ProgressView().controlSize(.small) }

            Button("Create an account") { openURL(Config.signupURL) }
                .textLinkStyle()
        }
        .padding(40)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboard(.email)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(loginWithPassword)
            Button("Log In", action: loginWithPassword)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(email.isEmpty || password.isEmpty)
            Button("Forgot password?") {
                run { try await auth.forgotPassword(email: email); info = "Password reset link sent to \(email)." }
            }
            .textLinkStyle()
            .disabled(email.isEmpty)
        }
    }

    private var phoneForm: some View {
        VStack(spacing: 12) {
            TextField("Phone number", text: $phone)
                .keyboard(.phone)
                .disabled(otpSent)
            if otpSent {
                TextField("OTP", text: $otp)
                    .keyboard(.oneTimeCode)
                    .onSubmit(verifyOTP)
                Button("Verify & Log In", action: verifyOTP)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(otp.isEmpty)
                Button("Change number") { otpSent = false; otp = "" }
                    .textLinkStyle()
            } else {
                Button("Send OTP") {
                    run { try await auth.sendOTP(phone: phone); otpSent = true; info = "OTP sent to \(phone)." }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(phone.isEmpty)
            }
        }
    }

    private func loginWithPassword() {
        run { try await auth.login(email: email.trimmingCharacters(in: .whitespaces), password: password) }
    }

    private func verifyOTP() {
        run { try await auth.verifyOTP(phone: phone, otp: otp) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        info = nil
        busy = true
        Task {
            do { try await action() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
