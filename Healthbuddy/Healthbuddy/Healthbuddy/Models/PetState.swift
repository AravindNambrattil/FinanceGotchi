import Foundation

struct SavingsGoal: Codable, Identifiable {
    let id: String
    let name: String
    let current: Double
    let target: Double

    var progress: Double { min(current / max(target, 1), 1.0) }
    var progressPercent: Int { Int(progress * 100) }
}

struct PetState: Codable, Identifiable {
    let petId: String
    let name: String
    let mood: String
    let needs: Double
    let energy: Double
    let savingsScore: Double      // 0–100 overall savings health
    let currentBalance: Double
    let emergencyFund: Double     // current emergency fund balance
    let emergencyFundTarget: Double
    let savingStreak: Int         // consecutive days of saving
    let goal: SavingsGoal?        // active long-term goal
    let message: String

    var id: String { petId }

    enum MoodExpression: String {
        case happy, sad, neutral, excited
    }

    var moodExpression: MoodExpression {
        MoodExpression(rawValue: mood) ?? .neutral
    }
}

// MARK: - Mock Data
extension PetState {
    static let mockMochi = PetState(
        petId: "mochi",
        name: "Mochi",
        mood: "happy",
        needs: 85,
        energy: 81,
        savingsScore: 72,
        currentBalance: 420.00,
        emergencyFund: 110.00,
        emergencyFundTarget: 500.00,
        savingStreak: 4,
        goal: SavingsGoal(id: "laptop", name: "Laptop", current: 720, target: 1000),
        message: "Mochi is proud of your saving streak!"
    )

    static let mockByte = PetState(
        petId: "byte",
        name: "Byte",
        mood: "excited",
        needs: 70,
        energy: 90,
        savingsScore: 58,
        currentBalance: 310.00,
        emergencyFund: 80.00,
        emergencyFundTarget: 500.00,
        savingStreak: 2,
        goal: SavingsGoal(id: "vacation", name: "Vacation", current: 350, target: 800),
        message: "Byte wants to hang out!"
    )
}
