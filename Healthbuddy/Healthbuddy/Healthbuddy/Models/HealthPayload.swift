import Foundation

struct HealthPayload: Codable {
    let steps: Int
    let activeEnergyKcal: Double
    let exerciseMinutes: Int
}

struct FinancialAction: Codable {
    let action: String
    let amount: Double
}

struct PetInteraction: Codable {
    let targetPetId: String
    let interactionType: String
}

struct ActionResponse: Codable {
    let message: String
    let petState: PetState?
}
