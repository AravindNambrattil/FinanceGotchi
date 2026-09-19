import Foundation

struct SavingsGoal: Codable, Identifiable {
    let id: String
    let name: String
    let current: Double
    let target: Double

    var progress: Double { min(current / max(target, 1), 1.0) }
    var progressPercent: Int { Int(progress * 100) }

    enum CodingKeys: String, CodingKey { case id, name, current, target }

    init(id: String, name: String, current: Double, target: Double) {
        self.id = id
        self.name = name
        self.current = current
        self.target = target
    }

    /// The backend's `db.get_pet` returns `{name, current, target}` with no `id` (and a numeric one once it
    /// does), so `id` is accepted as a String, an Int, or absent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        current = try c.decode(Double.self, forKey: .current)
        target = try c.decode(Double.self, forKey: .target)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = name.lowercased()
        }
    }
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

// MARK: - Copy helper
extension PetState {
    /// Every field is `let`, so the stateful mock service builds updated copies through this.
    /// `goal` is a double optional: pass `.some(nil)` to clear it, or omit the argument to keep it.
    func replacing(
        goal: SavingsGoal?? = nil,
        mood: String? = nil,
        savingsScore: Double? = nil,
        savingStreak: Int? = nil,
        message: String? = nil
    ) -> PetState {
        PetState(
            petId: petId,
            name: name,
            mood: mood ?? self.mood,
            needs: needs,
            energy: energy,
            savingsScore: savingsScore ?? self.savingsScore,
            currentBalance: currentBalance,
            emergencyFund: emergencyFund,
            emergencyFundTarget: emergencyFundTarget,
            savingStreak: savingStreak ?? self.savingStreak,
            goal: goal ?? self.goal,
            message: message ?? self.message
        )
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
