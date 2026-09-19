import Foundation
import Observation

/// Central configuration for the FinanceGotchi app.
/// Toggle `useMockData` to work offline without the Raspberry Pi backend.
@Observable
class AppSettings {
    static let shared = AppSettings()

    /// When true, all services return local mock data instead of hitting the network.
    var useMockData: Bool = true

    /// The active pet ID shown in the main UI.
    var activePetId: String = "mochi"

    /// Base URL of the Raspberry Pi backend.
    /// Change this to the Pi's mDNS name or IP address on the local network.
    var baseURLString: String = "http://financegotchi.local"

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: "http://financegotchi.local")!
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "baseURLString") {
            baseURLString = saved
        }
    }

    func saveBaseURL() {
        UserDefaults.standard.set(baseURLString, forKey: "baseURLString")
    }
}
