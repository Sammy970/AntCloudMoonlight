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
    @State private var failures = 0

    var body: some View {
        ZStack {
            AuroraBackground()
            #if os(iOS)
            // Phone: the hero stacks above the card and the whole screen scrolls with the keyboard.
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    card
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 24)
                // Exactly the screen's width, so nothing can push the page sideways.
                .containerRelativeFrame(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            #else
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 56) {
                    hero.frame(maxWidth: 340, alignment: .leading)
                    card
                }
                card
            }
            .padding(40)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transparentTitleBar()
        #if DEBUG
        .onAppear {
            // Screenshot mode fills sample credentials so the Sign In button shows its active state.
            if ProcessInfo.processInfo.environment["ANTCLOUD_PREVIEW"] == "login" {
                email = "player@example.com"
                password = "password"
            }
        }
        #endif
    }

    #if os(iOS)
    private static let isPhone = true
    #else
    private static let isPhone = false
    #endif

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Self.isPhone ? 18 : 22) {
            AppIconImage()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: Color.antBlue.opacity(0.6), radius: 18, y: 6)
                .reveal(0)

            VStack(alignment: .leading, spacing: 10) {
                Text("Your gaming PC,\nin the cloud.")
                    .font(.system(size: Self.isPhone ? 34 : 38, weight: .bold))
                    .lineSpacing(-2)
                Text(Self.isPhone ? "Start it, stream it, play. AntCloud on your iPhone, one tap at a time."
                                  : "Start it, stream it, play. AntCloud on your Mac, one click at a time.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .reveal(0.08)

            VStack(alignment: .leading, spacing: 10) {
                feature("power", "One click to start your cloud PC").reveal(0.16)
                feature("link", "Pairs with Moonlight on its own").reveal(0.22)
                feature("sparkles.tv", "Up to 4K and 120 FPS").reveal(0.28)
            }
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.antBlue.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(text).font(.callout.weight(.medium))
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Sign in").font(.title2.weight(.semibold))
                Text("Use your AntCloud account.").foregroundStyle(.secondary)
            }

            Picker("Sign in with", selection: $method) {
                ForEach(Method.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: method) { _ in error = nil; info = nil }

            Group {
                switch method {
                case .email: emailForm
                case .phone: phoneForm
                }
            }
            .loginFieldStyle()
            .disabled(busy)

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let info {
                Label(info, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 4) {
                Text("New to AntCloud?").foregroundStyle(.secondary)
                Button("Create an account") { openURL(Config.signupURL) }
                    .textLinkStyle()
            }
            .font(.callout)
        }
        .padding(Self.isPhone ? 22 : 28)
        .frame(maxWidth: Self.isPhone ? .infinity : 340)
        .glassSurface(cornerRadius: 28)
        .shadow(color: .black.opacity(0.18), radius: 30, y: 16)
        .modifier(Shake(animatableData: CGFloat(failures)))
        .reveal(Self.isPhone ? 0.3 : 0.18)
    }

    private var emailForm: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboard(.email)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(loginWithPassword)
            Button("Forgot password?") {
                run { try await auth.forgotPassword(email: email); info = "Password reset link sent to \(email)." }
            }
            .textLinkStyle()
            .font(.callout)
            .disabled(email.isEmpty)
            primaryButton("Sign In", action: loginWithPassword)
                .disabled(email.isEmpty || password.isEmpty)
                .padding(.top, 4)
        }
    }

    private var phoneForm: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Phone number", text: $phone)
                .keyboard(.phone)
                .disabled(otpSent)
            if otpSent {
                TextField("One-time code", text: $otp)
                    .keyboard(.oneTimeCode)
                    .onSubmit(verifyOTP)
                Button("Use a different number") { otpSent = false; otp = ""; info = nil }
                    .textLinkStyle()
                    .font(.callout)
                primaryButton("Verify & Sign In", action: verifyOTP)
                    .disabled(otp.isEmpty)
                    .padding(.top, 4)
            } else {
                Text("Indian numbers can skip the +91.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                primaryButton("Send Code") {
                    run { try await auth.sendOTP(phone: phone); otpSent = true; info = "Code sent to \(phone)." }
                }
                .disabled(phone.isEmpty)
                .padding(.top, 4)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).font(.body.weight(.semibold)).opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity)
        }
        .signInButtonStyle()
        .keyboardShortcut(.defaultAction)
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
            do {
                try await action()
            } catch {
                withAnimation(.easeOut(duration: 0.2)) { self.error = error.localizedDescription }
                withAnimation(.linear(duration: 0.45)) { failures += 1 }
            }
            busy = false
        }
    }
}

// MARK: - Sign-in button

private extension View {
        /// The gradient glow pill: stays clearly blue when disabled (just dimmer), where a disabled
    /// glass button turns grey and all but disappears on the glass card.
    func signInButtonStyle() -> some View {
        buttonStyle(GlowButtonStyle())
    }
}

/// Brand-gradient pill with a soft blue glow, for the sign-in action.
private struct GlowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .background(
                LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1), .antBlue, Color(red: 0.36, green: 0.36, blue: 0.9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Color.antBlue.opacity(isEnabled ? 0.5 : 0), radius: 12, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Aurora background

/// Slowly drifting blurred light in AntCloud blues. Still when Reduce Motion is on.
struct AuroraBackground: View {
    /// 1 on the sign-in screen; lower behind working screens so content stays calm.
    var intensity = 1.0

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Blob {
        let color: Color
        let size: CGFloat
        let x: Double, y: Double, speed: Double, phase: Double
    }

    private var blobs: [Blob] {
        [
            Blob(color: .antBlue, size: 760, x: 0.18, y: 0.25, speed: 0.11, phase: 0),
            Blob(color: Color(red: 0.36, green: 0.36, blue: 0.9), size: 680, x: 0.85, y: 0.2, speed: 0.08, phase: 2),
            Blob(color: Color(red: 0.25, green: 0.78, blue: 0.98), size: 640, x: 0.7, y: 0.85, speed: 0.13, phase: 4),
            Blob(color: .antBlue, size: 560, x: 0.3, y: 0.9, speed: 0.09, phase: 1),
        ]
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    base
                    ForEach(blobs.indices, id: \.self) { i in
                        let b = blobs[i]
                        Circle()
                            .fill(RadialGradient(
                                colors: [b.color.opacity((scheme == .dark ? 0.6 : 0.4) * intensity), b.color.opacity(0)],
                                center: .center, startRadius: 0, endRadius: b.size / 2))
                            .frame(width: b.size, height: b.size)
                            .position(
                                x: geo.size.width * (b.x + 0.08 * cos(t * b.speed + b.phase)),
                                y: geo.size.height * (b.y + 0.08 * sin(t * b.speed * 1.3 + b.phase))
                            )
                    }
                }
                .overlay(grid)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var base: some View {
        scheme == .dark
            ? LinearGradient(colors: [Color(red: 0.03, green: 0.06, blue: 0.14), Color(red: 0.05, green: 0.09, blue: 0.2)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 1), Color(red: 0.86, green: 0.91, blue: 1)], startPoint: .top, endPoint: .bottom)
    }

    /// Faint dot grid that fades toward the edges, for a sense of depth.
    private var grid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.5, height: 1.5))
            for x in stride(from: step / 2, to: size.width, by: step) {
                for y in stride(from: step / 2, to: size.height, by: step) {
                    ctx.fill(dot.offsetBy(dx: x, dy: y), with: .color(scheme == .dark ? .white.opacity(0.07) : .black.opacity(0.06)))
                }
            }
        }
        .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 80, endRadius: 520))
    }
}
