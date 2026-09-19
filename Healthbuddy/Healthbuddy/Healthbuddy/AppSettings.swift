import Foundation
import Observation

/// Central configuration for the FinanceGotchi app.
@Observable
class AppSettings {
    static let shared = AppSettings()

    /// The deployed backend (Vultr). HTTPS is required: iOS blocks plain `http://` calls.
    static let liveServerURL = "https://66-42-93-22.sslip.io"

    private enum Key {
        static let useMockData = "fg.useMockData"
        static let baseURL = "fg.baseURLString"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// When true, all pet/finance services return local demo data instead of calling the server.
    /// Off by default (live). Flip it from the Account card if the network is unreliable.
    var useMockData: Bool { didSet { defaults.set(useMockData, forKey: Key.useMockData) } }

    /// When true, goals come from the server's `/pets/{id}/goals` endpoints. Those don't exist yet (see CLAUDE.md,
    /// "Backend contract for goals"), so goals stay on this device until they ship.
    var useServerGoals: Bool = false

    /// The active pet ID shown in the main UI.
    var activePetId: String = "mochi"

    var baseURLString: String { didSet { defaults.set(baseURLString, forKey: Key.baseURL) } }

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: Self.liveServerURL)!
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        useMockData = defaults.object(forKey: Key.useMockData) as? Bool ?? false
        baseURLString = defaults.string(forKey: Key.baseURL) ?? Self.liveServerURL
    }
}
