import Foundation

struct HealthPayload: Codable {
    let steps: Int
    let activeEnergyKcal: Double
    let exerciseMinutes: Int
}

struct FinancialAction: Codable {
    let action: String
    let amount: Double
    /// Which goal a `save_instead` lands on. Omitted for other actions.
    var goalId: String? = nil
    /// The pending offer this decision resolves.
    var offerId: Int? = nil
}

struct PetInteraction: Codable {
    let targetPetId: String
    let interactionType: String
}

struct ActionResponse: Codable {
    let message: String
    let petState: PetState?
    /// Set when the action credited a goal, so the UI can show exactly what changed.
    var contribution: Contribution? = nil
    var goal: Goal? = nil
    var milestoneCrossed: GoalMilestone? = nil
}
