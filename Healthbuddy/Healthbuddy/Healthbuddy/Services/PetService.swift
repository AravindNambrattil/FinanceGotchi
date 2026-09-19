import Foundation

protocol PetServiceProtocol {
    func fetchPetState(petId: String) async throws -> PetState
    func fetchTransactions(petId: String) async throws -> [Transaction]
    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse
    func sendHealth(petId: String, payload: HealthPayload) async throws -> ActionResponse
    func sendInteraction(petId: String, interaction: PetInteraction) async throws -> ActionResponse
}

// MARK: - Live Service
final class PetService: PetServiceProtocol {
    private let api: APIClient
    private let settings: AppSettings

    init(api: APIClient = .shared, settings: AppSettings = .shared) {
        self.api = api
        self.settings = settings
    }

    func fetchPetState(petId: String) async throws -> PetState {
        try await api.get("/api/pets/\(petId)/state", baseURL: settings.baseURL)
    }

    func fetchTransactions(petId: String) async throws -> [Transaction] {
        try await api.get("/api/pets/\(petId)/transactions", baseURL: settings.baseURL)
    }

    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse {
        try await api.post("/api/pets/\(petId)/actions", body: action, baseURL: settings.baseURL)
    }

    func sendHealth(petId: String, payload: HealthPayload) async throws -> ActionResponse {
        try await api.post("/api/pets/\(petId)/health", body: payload, baseURL: settings.baseURL)
    }

    func sendInteraction(petId: String, interaction: PetInteraction) async throws -> ActionResponse {
        try await api.post("/api/pets/\(petId)/interactions", body: interaction, baseURL: settings.baseURL)
    }
}

// MARK: - Mock Service
/// Stateful stand-in for the backend: saving really moves the goal, and the pet and transaction list follow.
/// Goals live in the injected store; previews default to an in-memory one so they never touch disk.
final class MockPetService: PetServiceProtocol {
    private let goals: GoalStoreProtocol
    private var states: [String: PetState] = ["mochi": .mockMochi, "byte": .mockByte]
    private var recorded: [Transaction] = []

    init(goalStore: GoalStoreProtocol = LocalGoalStore.inMemory()) {
        self.goals = goalStore
    }

    func fetchPetState(petId: String) async throws -> PetState {
        try await currentState(petId: petId)
    }

    func fetchTransactions(petId: String) async throws -> [Transaction] {
        recorded.reversed() + Transaction.mockTransactions
    }

    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse {
        try await Task.sleep(nanoseconds: 400_000_000)

        switch action.action {
        case "save_instead":
            return try await saveInstead(petId: petId, action: action)
        case "buy":
            recorded.append(Transaction(id: UUID().uuidString, title: "New Headphones", amount: -action.amount, category: "expense"))
            return ActionResponse(
                message: "Mochi understands! Just remember to balance needs and wants.",
                petState: try await currentState(petId: petId)
            )
        case "defer":
            return ActionResponse(
                message: "Good thinking! Planning ahead keeps Mochi happy.",
                petState: try await currentState(petId: petId)
            )
        default:
            return ActionResponse(message: "Action recorded.", petState: try await currentState(petId: petId))
        }
    }

    func sendHealth(petId: String, payload: HealthPayload) async throws -> ActionResponse {
        try await Task.sleep(nanoseconds: 300_000_000)
        return ActionResponse(message: "Mochi gained energy from your activity!", petState: try await currentState(petId: petId))
    }

    func sendInteraction(petId: String, interaction: PetInteraction) async throws -> ActionResponse {
        try await Task.sleep(nanoseconds: 400_000_000)
        return ActionResponse(message: "Mochi and Byte hung out together. Mood +5!", petState: try await currentState(petId: petId))
    }

    // MARK: - Helpers
    /// The one place a save credits a goal. Callers must not also call `addContribution`.
    private func saveInstead(petId: String, action: FinancialAction) async throws -> ActionResponse {
        let snapshot = try await goals.fetchSnapshot(petId: petId)
        guard let goalId = action.goalId ?? snapshot.primaryGoal?.id else {
            return ActionResponse(
                message: "Set a savings goal first so Mochi knows where this goes.",
                petState: try await currentState(petId: petId)
            )
        }

        let result = try await goals.addContribution(
            petId: petId,
            goalId: goalId,
            draft: ContributionDraft(amount: action.amount, source: .savedInstead, note: "Saved instead of spending")
        )

        // BACKEND OWNS THIS: the savings-score bump and mood are financial policy (db.apply_decision).
        if let state = states[petId] {
            states[petId] = state.replacing(
                mood: result.milestoneCrossed != nil ? "excited" : nil,
                savingsScore: min(state.savingsScore + 5, 100)
            )
        }
        recorded.append(Transaction(id: result.contribution.id, title: "Saved for \(result.goal.name)", amount: action.amount, category: "savings"))

        return ActionResponse(
            message: result.message ?? "Nice! You saved $\(String(format: "%.2f", action.amount)) towards your goal!",
            petState: try await currentState(petId: petId),
            contribution: result.contribution,
            goal: result.goal,
            milestoneCrossed: result.milestoneCrossed
        )
    }

    /// Pet state with `goal` always taken from the store's primary goal.
    private func currentState(petId: String) async throws -> PetState {
        let base = states[petId] ?? .mockMochi
        let snapshot = try await goals.fetchSnapshot(petId: petId)
        let primary: SavingsGoal?? = .some(snapshot.primaryGoal?.asSavingsGoal)
        return base.replacing(goal: primary)
    }
}

// MARK: - Factory
extension PetService {
    /// Shared so every view model sees the same mock pet state and the same goals.
    private static let sharedMock = MockPetService(goalStore: GoalStoreFactory.make())

    static func makeService(settings: AppSettings = .shared) -> PetServiceProtocol {
        settings.useMockData ? sharedMock : PetService(settings: settings)
    }
}
