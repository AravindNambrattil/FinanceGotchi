import Foundation

// MARK: - Enums

enum GoalKind: String, Codable {
    case custom, emergency, other

    /// Unknown server values must not fail the whole goal list.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GoalKind(rawValue: raw) ?? .other
    }
}

enum GoalStatus: String, Codable {
    case active, done, archived

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GoalStatus(rawValue: raw) ?? .active
    }
}

/// The 0–25 / 25–50 / 50–75 / 75–99 / 100 % bands Mochi reacts to (see CLAUDE.md, "Long-term goals").
/// Int raw values are stable so the backend can send `"milestone": 2` later.
enum GoalMilestone: Int, Codable, Comparable, CaseIterable {
    case starting = 0, growing, halfway, almost, reached

    init(progress: Double) {
        switch progress {
        case 1.0...:  self = .reached
        case 0.75...: self = .almost
        case 0.50...: self = .halfway
        case 0.25...: self = .growing
        default:      self = .starting
        }
    }

    static func < (lhs: GoalMilestone, rhs: GoalMilestone) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Goal

struct Goal: Codable, Identifiable, Hashable {
    let id: String
    var kind: GoalKind
    var name: String
    /// SF Symbol name. Emoji render as `?` on the iOS 26 simulator, so goals use symbols.
    var symbol: String
    var current: Double
    var target: Double
    var deadline: Date?
    var status: GoalStatus
    var createdAt: Date
    /// Band supplied by the backend. When nil, `milestone` is derived from progress.
    var serverMilestone: GoalMilestone?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, symbol, current, target, deadline, status, createdAt
        case serverMilestone = "milestone"
    }

    init(
        id: String = UUID().uuidString,
        kind: GoalKind = .custom,
        name: String,
        symbol: String = "star.fill",
        current: Double = 0,
        target: Double,
        deadline: Date? = nil,
        status: GoalStatus = .active,
        createdAt: Date = .now,
        serverMilestone: GoalMilestone? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.symbol = symbol
        self.current = current
        self.target = target
        self.deadline = deadline
        self.status = status
        self.createdAt = createdAt
        self.serverMilestone = serverMilestone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // FastAPI sends `"id": 3` as a JSON number; local goals use UUID strings. Accept both.
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        kind = (try? c.decode(GoalKind.self, forKey: .kind)) ?? .custom
        name = try c.decode(String.self, forKey: .name)
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? "star.fill"
        current = try c.decode(Double.self, forKey: .current)
        target = try c.decode(Double.self, forKey: .target)
        deadline = try? c.decode(Date.self, forKey: .deadline)
        status = (try? c.decode(GoalStatus.self, forKey: .status)) ?? .active
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? .now
        serverMilestone = try? c.decode(GoalMilestone.self, forKey: .serverMilestone)
    }
}

// MARK: - Derived values
// Arithmetic only. Whether the user is "on track" is financial policy and stays with the backend.
extension Goal {
    var progress: Double { min(max(current / max(target, 0.01), 0), 1) }
    var progressPercent: Int { Int((progress * 100).rounded(.down)) }
    var remaining: Double { max(target - current, 0) }
    var isComplete: Bool { current >= target }
    var milestone: GoalMilestone { serverMilestone ?? GoalMilestone(progress: progress) }

    var daysRemaining: Int? {
        guard let deadline else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: deadline)).day
    }

    var isPastDeadline: Bool { (daysRemaining ?? 0) < 0 }

    /// Dollars per week needed to land on the deadline. Nil with no deadline, nothing left, or a passed deadline.
    var requiredPerWeek: Double? {
        guard let days = daysRemaining, days >= 0, remaining > 0 else { return nil }
        return remaining / max(Double(days) / 7, 1.0 / 7)
    }

    /// Bridge to the backend's wire shape for the single primary goal, so `PetState.goal` keeps working.
    var asSavingsGoal: SavingsGoal {
        SavingsGoal(id: id, name: name, current: current, target: target)
    }
}

// MARK: - Draft
/// Input for create and update. `current` is deliberately absent: a balance only moves via a contribution.
struct GoalDraft: Codable, Hashable {
    var name: String
    var symbol: String
    var target: Double
    var deadline: Date?
    var kind: GoalKind = .custom

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && target > 0
    }
}

// MARK: - Snapshot
struct GoalsSnapshot: Codable {
    var goals: [Goal]
    /// The goal Mochi reacts to and the Pet tab shows. Held here, not as `Goal.isPrimary`, so
    /// "exactly one primary" cannot be violated. Named "primary" because the backend already uses
    /// `status='active'` to mean "not done".
    var primaryGoalId: String?

    init(goals: [Goal], primaryGoalId: String?) {
        self.goals = goals
        self.primaryGoalId = primaryGoalId
    }

    enum CodingKeys: String, CodingKey { case goals, primaryGoalId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goals = try c.decode([Goal].self, forKey: .goals)
        // The backend sends the primary id as a number.
        if let s = try? c.decode(String.self, forKey: .primaryGoalId) {
            primaryGoalId = s
        } else if let i = try? c.decode(Int.self, forKey: .primaryGoalId) {
            primaryGoalId = String(i)
        } else {
            primaryGoalId = nil
        }
    }

    /// Goals shown in the Goals list. The emergency fund has its own card.
    var trackedGoals: [Goal] {
        goals.filter { $0.kind != .emergency && $0.status != .archived }
    }

    var primaryGoal: Goal? {
        trackedGoals.first { $0.id == primaryGoalId }
            ?? trackedGoals.first { $0.status == .active }
    }

    var emergencyGoal: Goal? { goals.first { $0.kind == .emergency } }

    static let empty = GoalsSnapshot(goals: [], primaryGoalId: nil)
}
