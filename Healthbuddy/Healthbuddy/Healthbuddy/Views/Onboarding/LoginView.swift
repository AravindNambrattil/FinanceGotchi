import SwiftUI

/// Demo sign-in. Accepts any well-formed email and a password of 6+ characters; nothing is created, sent, or
/// stored except the email and a display name. The password is cleared as soon as it is used.
struct LoginView: View {
    var session: SessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var showValidation = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var emailValid: Bool { SessionStore.isValidEmail(email) }
    private var passwordValid: Bool { password.count >= SessionStore.minimumPasswordLength }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(title: "Welcome back", subtitle: "Mochi missed you. Sign in to keep going.")
                    demoBanner
                    fields
                    signInButton
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero
    private var hero: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .overlay { heroArt }
            .clipped()
    }

    private var heroArt: some View {
        ZStack {
            Ellipse()
                .fill(Theme.yellow)
                .frame(width: 520, height: 330)
                .offset(x: -70, y: -90)
            Capsule().fill(Theme.coral).frame(width: 64, height: 16).rotationEffect(.degrees(-6)).offset(x: -120, y: -50)
            Capsule().fill(Theme.pink).frame(width: 64, height: 16).rotationEffect(.degrees(-6)).offset(x: -104, y: -26)
            Image(systemName: "camera.macro")
                .font(.system(size: 54))
                .foregroundStyle(Theme.coral)
                .rotationEffect(.degrees(12))
                .offset(x: 124, y: -66)
                .accessibilityHidden(true)
            MochiView(mood: .happy, milestone: .halfway, size: 130)
                .offset(y: 10)
        }
    }

    // MARK: - Demo notice
    private var demoBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.indigo)
            Text("Demo mode: no account is created and nothing is sent anywhere.")
                .font(Theme.caption)
                .foregroundStyle(Theme.onPastel)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sky.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Fields
    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(title: "Email", error: showValidation && !emailValid ? "Enter a valid email address." : nil) {
                TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com"))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }

            field(
                title: "Password",
                error: showValidation && !passwordValid ? "Use at least \(SessionStore.minimumPasswordLength) characters." : nil
            ) {
                SecureField("At least \(SessionStore.minimumPasswordLength) characters", text: $password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            }
        }
    }

    private func field<Content: View>(title: String, error: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            content()
                .padding(14)
                .background(Theme.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(Theme.onPastel)
                .overlay {
                    if error != nil {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.coral, lineWidth: 2)
                    }
                }
            if let error {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    private var signInButton: some View {
        Button(action: submit) {
            Text("Sign in")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(MellowFilledButtonStyle(fill: Theme.navy))
        .padding(.top, 4)
    }

    private func submit() {
        guard emailValid, passwordValid else {
            showValidation = true
            return
        }
        // Discard the password before anything else happens; it is never stored or sent.
        password = ""
        focus = nil
        session.signIn(email: email)
    }
}

#Preview {
    LoginView(session: SessionStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
}
