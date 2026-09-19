import Foundation

/// Whether the physical pet (the Raspberry Pi) has been heard from recently. Comes from `GET /pets/{id}/device`.
struct DeviceStatus: Codable, Equatable {
    let connected: Bool
    let lastSync: String?
    let secondsAgo: Int?

    /// "Connected just now", "Last seen 2 min ago", or "Not paired yet".
    var summary: String {
        guard let secondsAgo else { return "Not paired yet" }
        let age: String
        switch secondsAgo {
        case ..<6:   age = "just now"
        case ..<60:  age = "\(secondsAgo)s ago"
        case ..<3600: age = "\(secondsAgo / 60) min ago"
        default:     age = "\(secondsAgo / 3600) h ago"
        }
        return connected ? "Connected \(age)" : "Last seen \(age)"
    }
}
