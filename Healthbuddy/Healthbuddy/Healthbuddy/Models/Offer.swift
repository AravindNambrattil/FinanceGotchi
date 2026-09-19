import Foundation

/// A "Mochi wants..." prompt. The server holds one pending offer at a time; deciding on it resolves it.
struct Offer: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let cost: Double
    /// "essential" or "want". Essentials give Mochi needs; impulse wants slow savings a little.
    let category: String

    var isEssential: Bool { category == "essential" }

    /// "Mochi wants new headphones" from the title "New headphones".
    var prompt: String {
        guard let first = title.first else { return "Mochi wants something" }
        return "Mochi wants \(first.lowercased())\(title.dropFirst())"
    }

    var systemImage: String {
        let lower = title.lowercased()
        if lower.contains("headphone") { return "headphones" }
        if lower.contains("laptop") || lower.contains("computer") { return "laptopcomputer" }
        if lower.contains("phone") { return "iphone" }
        return isEssential ? "cart.fill" : "gift.fill"
    }
}

extension Offer {
    /// Wants Mochi cycles through in demo mode. The live server only has one seeded offer.
    static let mockCycle: [Offer] = [
        Offer(id: 1, title: "New headphones", cost: 25, category: "want"),
        Offer(id: 2, title: "Concert tickets", cost: 40, category: "want"),
        Offer(id: 3, title: "Winter jacket", cost: 35, category: "essential"),
        Offer(id: 4, title: "Takeout dinner", cost: 18, category: "want"),
    ]
}
