import Foundation
import Observation

@Observable
@MainActor
final class FinancialViewModel {
    var transactions: [Transaction] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // Decision state
    var isSendingAction: Bool = false
    var decisionResult: String?
    var selectedAction: String?

    @ObservationIgnored private let service: PetServiceProtocol
    @ObservationIgnored private let settings: AppSettings

    init(service: PetServiceProtocol? = nil, settings: AppSettings = .shared) {
        self.settings = settings
        self.service = service ?? PetService.makeService(settings: settings)
    }

    // MARK: - Load Transactions
    func loadTransactions() async {
        isLoading = true
        errorMessage = nil
        do {
            transactions = try await service.fetchTransactions(petId: settings.activePetId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Send Financial Decision
    func sendDecision(action: String, amount: Double = 25.00) async {
        guard !isSendingAction else { return }
        selectedAction = action
        isSendingAction = true
        decisionResult = nil
        let payload = FinancialAction(action: action, amount: amount)
        do {
            let response = try await service.sendAction(petId: settings.activePetId, action: payload)
            decisionResult = response.message
        } catch {
            decisionResult = error.localizedDescription
        }
        isSendingAction = false
    }

    func clearDecisionResult() {
        decisionResult = nil
        selectedAction = nil
    }
}
