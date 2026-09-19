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
final class MockPetService: PetServiceProtocol {
    func fetchPetState(petId: String) async throws -> PetState {
        return petId == "byte" ? .mockByte : .mockMochi
    }

    func fetchTransactions(petId: String) async throws -> [Transaction] {
        return Transaction.mockTransactions
    }

    func sendAction(petId: String, action: FinancialAction) async throws -> ActionResponse {
        try await Task.sleep(nanoseconds: 400_000_000)
        let message: String
        switch action.action {
        case "buy":
            message = "Mochi understands! Just remember to balance needs and wants."
        case "save_instead":
            message = "Nice! You saved $\(String(format: "%.2f", action.amount)) towards your goal!"
        case "defer":
            message = "Good thinking! Planning ahead keeps Mochi happy."
        default:
            message = "Action recorded."
        }
        return ActionResponse(message: message, petState: .mockMochi)
    }

    func sendHealth(petId: String, payload: HealthPayload) async throws -> ActionResponse {
        try await Task.sleep(nanoseconds: 300_000_000)
        return ActionResponse(message: "Mochi gained energy from your activity!", petState: .mockMochi)
    }

    func sendInteraction(petId: String, interaction: PetInteraction) async throws -> ActionResponse {
        try await Task.sleep(nanoseconds: 400_000_000)
        return ActionResponse(message: "Mochi and Byte hung out together. Mood +5!", petState: .mockMochi)
    }
}

// MARK: - Factory
extension PetService {
    static func makeService(settings: AppSettings = .shared) -> PetServiceProtocol {
        settings.useMockData ? MockPetService() : PetService(settings: settings)
    }
}
