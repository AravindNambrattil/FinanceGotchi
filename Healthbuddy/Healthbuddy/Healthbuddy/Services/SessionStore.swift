import Foundation
import Observation

/// Local, demo-only session. There is no auth backend, so nothing here is secure and nothing is sent anywhere.
///
/// Only the intro flag, email, and a display name are persisted. **Passwords are never stored:** the login
/// screen validates one in local state and discards it.
@Observable
@MainActor
final class SessionStore {
    private enum Key {
        static let hasOnboarded = "fg.hasOnboarded"
        static let isSignedIn = "fg.isSignedIn"
        static let email = "fg.email"
        static let displayName = "fg.displayName"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    var isSignedIn: Bool { didSet { defaults.set(isSignedIn, forKey: Key.isSignedIn) } }
    var email: String { didSet { defaults.set(email, forKey: Key.email) } }
    var displayName: String { didSet { defaults.set(displayName, forKey: Key.displayName) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        isSignedIn = defaults.bool(forKey: Key.isSignedIn)
        email = defaults.string(forKey: Key.email) ?? ""
        displayName = defaults.string(forKey: Key.displayName) ?? ""
    }

    /// Demo sign-in: any well-formed email is accepted.
    func signIn(email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = trimmed
        displayName = Self.displayName(from: trimmed)
        hasOnboarded = true
        isSignedIn = true
    }

    func signOut() {
        isSignedIn = false
    }

    /// Shows the landing page and onboarding again on the next screen.
    func replayIntro() {
        isSignedIn = false
        hasOnboarded = false
    }

    // MARK: - Validation
    static func isValidEmail(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    static let minimumPasswordLength = 6

    private static func displayName(from email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? ""
        let letters = local.prefix { $0.isLetter }
        return letters.isEmpty ? "Friend" : letters.prefix(1).uppercased() + letters.dropFirst()
    }
}
