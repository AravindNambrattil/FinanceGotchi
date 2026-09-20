import Foundation

protocol PetServiceProtocol {
    func fetchPetState(petId: String) async throws -> PetState
    func fetchTransactions(petId: String) async throws -> [Transaction]
    /// The pending "Mochi wants..." prompt, or nil when there isn't one.
    func fetchOffer(petId: String) async throws -> Offer?
    /// Whether the physical pet (Raspberry Pi) is online.
    func fetchDeviceStatus(petId: String) async throws -> DeviceStatus
    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse
    func sendHealth(petId: String, payload: HealthPayload) async throws -> ActionResponse
    func sendInteraction(petId: String, interaction: PetInteraction) async throws -> ActionResponse
}

// MARK: - Live Service
/// Talks to the deployed FastAPI backend and translates its JSON into the app's models. All the translation lives
/// here so views and view models never see server shapes.
///
/// Financial rules stay on the server: it moves the money in Nessie and updates the pet. The app only presents
/// the result. Goals are the one exception for now: the server has a single goal and no goal endpoints yet, so
/// goals live in the local store and a save is credited there after the server accepts it.
final class PetService: PetServiceProtocol {
    private let api: APIClient
    private let settings: AppSettings
    private let goals: GoalStoreProtocol

    init(api: APIClient = .shared, settings: AppSettings = .shared, goals: GoalStoreProtocol? = nil) {
        self.api = api
        self.settings = settings
        self.goals = goals ?? GoalStoreFactory.make(settings: settings)
    }

    // MARK: Reads
    func fetchPetState(petId: String) async throws -> PetState {
        async let pet: BackendPet = api.get("/pets/\(petId)", baseURL: settings.baseURL)
        async let finance: BackendFinance = api.get("/pets/\(petId)/finance", baseURL: settings.baseURL)
        let (backendPet, backendFinance) = try await (pet, finance)
        return await state(from: backendPet, finance: backendFinance)
    }

    func fetchTransactions(petId: String) async throws -> [Transaction] {
        let finance: BackendFinance = try await api.get("/pets/\(petId)/finance", baseURL: settings.baseURL)
        return finance.recentActivity.map(Self.transaction)
    }

    func fetchOffer(petId: String) async throws -> Offer? {
        try await api.get("/pets/\(petId)/offer", baseURL: settings.baseURL)
    }

    func fetchDeviceStatus(petId: String) async throws -> DeviceStatus {
        try await api.get("/pets/\(petId)/device", baseURL: settings.baseURL)
    }

    // MARK: Writes
    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse {
        let body = BackendDecisionBody(choice: Self.choice(for: action.action), amount: action.amount, offerId: action.offerId)
        let result: BackendPet = try await api.post("/pets/\(petId)/decision", body: body, baseURL: settings.baseURL)

        // The server has accepted the decision (and moved the money), so this is the one place a save is credited
        // to a goal. Nothing else may credit it, or the amount is counted twice.
        var contribution: ContributionResult?
        if action.action == "save_instead", let goalId = action.goalId, !settings.useServerGoals {
            contribution = try? await goals.addContribution(
                petId: petId,
                goalId: goalId,
                draft: ContributionDraft(amount: action.amount, source: .savedInstead, note: "Saved instead of spending")
            )
        }

        let refreshed = try? await fetchPetState(petId: petId)
        return ActionResponse(
            message: contribution?.message ?? result.message ?? "Done.",
            petState: refreshed,
            contribution: contribution?.contribution,
            goal: contribution?.goal,
            milestoneCrossed: contribution?.milestoneCrossed
        )
    }

    func sendHealth(petId: String, payload: HealthPayload) async throws -> ActionResponse {
        // The server has no Apple Health endpoint yet, so there is nothing to send.
        ActionResponse(message: "Activity noted on this device. Mochi's server doesn't track Apple Health yet.", petState: nil)
    }

    func sendInteraction(petId: String, interaction: PetInteraction) async throws -> ActionResponse {
        let action = interaction.interactionType == "hang_out" ? "play" : "pet"
        let _: BackendPet = try await api.post("/pets/\(petId)/interact", body: BackendInteractBody(action: action), baseURL: settings.baseURL)
        let refreshed = try? await fetchPetState(petId: petId)
        return ActionResponse(message: "Mochi had fun playing!", petState: refreshed)
    }

    // MARK: Translation
    private func state(from pet: BackendPet, finance: BackendFinance) async -> PetState {
        // Goals come from the local store until the server has goal endpoints; fall back to the server's single goal.
        let local = try? await goals.fetchSnapshot(petId: pet.id)
        let goal = local?.primaryGoal?.asSavingsGoal ?? pet.goal

        return PetState(
            petId: pet.id,
            name: pet.name,
            mood: Self.moodName(pet.mood),
            needs: Double(pet.needs),
            energy: Double(pet.energy),
            savingsScore: Double(pet.savingsScore),
            currentBalance: finance.bank.checking ?? 0,
            emergencyFund: finance.emergencyFund?.current ?? 0,
            emergencyFundTarget: finance.emergencyFund?.target ?? 500,
            savingStreak: pet.streak,
            goal: goal,
            message: Self.message(for: pet)
        )
    }

    /// The server stores mood as 0-100; the app shows a face. This is display bucketing only, not a rule.
    static func moodName(_ mood: Int) -> String {
        switch mood {
        case 85...: "excited"
        case 60...: "happy"
        case 40...: "neutral"
        default:    "sad"
        }
    }

    private static func message(for pet: BackendPet) -> String {
        if pet.mood < 40 { return "\(pet.name) could use a little attention." }
        if pet.streak > 0 { return "\(pet.name) is proud of your \(pet.streak)-day saving streak!" }
        return "\(pet.name) is ready when you are."
    }

    /// The app's action names differ from the server's `choice` values.
    static func choice(for action: String) -> String {
        switch action {
        case "save_instead": "save"
        case "defer":        "later"
        default:             action   // "buy"
        }
    }

    private static func transaction(_ row: BackendActivity) -> Transaction {
        let title = row.description?.isEmpty == false ? row.description! : row.category.capitalized
        return Transaction(id: String(row.id), title: title, amount: row.amount, category: row.category)
    }
}

// MARK: - Mock Service
/// Stateful stand-in for the backend: saving really moves the goal, and the pet and transaction list follow.
/// Goals live in the injected store; previews default to an in-memory one so they never touch disk.
final class MockPetService: PetServiceProtocol {
    private let goals: GoalStoreProtocol
    private var states: [String: PetState] = ["mochi": .mockMochi, "byte": .mockByte]
    private var recorded: [Transaction] = []
    private var offerIndex = 0

    private var currentOffer: Offer { Offer.mockCycle[offerIndex % Offer.mockCycle.count] }

    init(goalStore: GoalStoreProtocol = LocalGoalStore.inMemory()) {
        self.goals = goalStore
    }

    func fetchPetState(petId: String) async throws -> PetState {
        try await currentState(petId: petId)
    }

    func fetchTransactions(petId: String) async throws -> [Transaction] {
        recorded.reversed() + Transaction.mockTransactions
    }

    func fetchOffer(petId: String) async throws -> Offer? {
        currentOffer
    }

    func fetchDeviceStatus(petId: String) async throws -> DeviceStatus {
        DeviceStatus(connected: true, lastSync: nil, secondsAgo: 1)
    }

    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse {
        try await Task.sleep(nanoseconds: 400_000_000)
        defer { offerIndex += 1 }   // whatever was decided, Mochi moves on to the next want

        switch action.action {
        case "save_instead":
            return try await saveInstead(petId: petId, action: action)
        case "buy":
            recorded.append(Transaction(id: UUID().uuidString, title: currentOffer.title, amount: -action.amount, category: "purchase"))
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

// MARK: - Adaptive service
/// Picks demo or live data on every call, so the "Use live server" switch takes effect immediately.
final class AdaptivePetService: PetServiceProtocol {
    private let settings: AppSettings
    private let live: PetService
    private let mock: MockPetService

    init(settings: AppSettings, live: PetService, mock: MockPetService) {
        self.settings = settings
        self.live = live
        self.mock = mock
    }

    private var current: PetServiceProtocol { settings.useMockData ? mock : live }

    func fetchPetState(petId: String) async throws -> PetState { try await current.fetchPetState(petId: petId) }
    func fetchTransactions(petId: String) async throws -> [Transaction] { try await current.fetchTransactions(petId: petId) }
    func fetchOffer(petId: String) async throws -> Offer? { try await current.fetchOffer(petId: petId) }
    func fetchDeviceStatus(petId: String) async throws -> DeviceStatus { try await current.fetchDeviceStatus(petId: petId) }
    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse { try await current.sendAction(petId: petId, action: action) }
    func sendHealth(petId: String, payload: HealthPayload) async throws -> ActionResponse { try await current.sendHealth(petId: petId, payload: payload) }
    func sendInteraction(petId: String, interaction: PetInteraction) async throws -> ActionResponse { try await current.sendInteraction(petId: petId, interaction: interaction) }
}

// MARK: - Factory
extension PetService {
    /// Shared so every view model sees the same demo pet state and the same goals.
    private static let sharedMock = MockPetService(goalStore: GoalStoreFactory.make())

    static func makeService(settings: AppSettings = .shared) -> PetServiceProtocol {
        AdaptivePetService(settings: settings, live: PetService(settings: settings), mock: sharedMock)
    }
}
