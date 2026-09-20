import Foundation

enum ContributionSource: String, Codable, CaseIterable {
    case manual
    /// "Save It" on a financial decision.
    case savedInstead = "saved_instead"
    case roundUp = "round_up"
    /// Opening balance for seeded demo data.
    case seed
    case correction
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ContributionSource(rawValue: raw) ?? .other
    }

    var title: String {
        switch self {
        case .manual:       "Added"
        case .savedInstead: "Saved instead"
        case .roundUp:      "Round-up"
        case .seed:         "Starting balance"
        case .correction:   "Correction"
        case .other:        "Contribution"
        }
    }

    var systemImage: String {
        switch self {
        case .manual:       "plus.circle.fill"
        case .savedInstead: "hand.thumbsup.fill"
        case .roundUp:      "arrow.up.circle.fill"
        case .seed:         "flag.fill"
        case .correction:   "arrow.uturn.backward.circle.fill"
        case .other:        "banknote.fill"
        }
    }
}

struct Contribution: Codable, Identifiable, Hashable {
    let id: String
    let goalId: String
    /// Signed. A negative amount is a withdrawal or correction.
    var amount: Double
    var date: Date
    var source: ContributionSource
    var note: String?

    var isWithdrawal: Bool { amount < 0 }

    init(
        id: String = UUID().uuidString,
        goalId: String,
        amount: Double,
        date: Date = .now,
        source: ContributionSource = .manual,
        note: String? = nil
    ) {
        self.id = id
        self.goalId = goalId
        self.amount = amount
        self.date = date
        self.source = source
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case id, goalId, amount, date, source, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        if let s = try? c.decode(String.self, forKey: .goalId) {
            goalId = s
        } else {
            goalId = String(try c.decode(Int.self, forKey: .goalId))
        }
        amount = try c.decode(Double.self, forKey: .amount)
        date = try c.decode(Date.self, forKey: .date)
        source = (try? c.decode(ContributionSource.self, forKey: .source)) ?? .other
        note = try? c.decode(String.self, forKey: .note)
    }
}

struct ContributionDraft: Codable {
    var amount: Double
    var source: ContributionSource = .manual
    var note: String?
    var date: Date = .now
}

/// The writer returns the authoritative post-write goal, so the UI never has to recompute it.
struct ContributionResult: Codable {
    var contribution: Contribution
    var goal: Goal
    /// Set when this contribution moved the goal into a higher band. Drives the celebration.
    var milestoneCrossed: GoalMilestone?
    var message: String?
}
