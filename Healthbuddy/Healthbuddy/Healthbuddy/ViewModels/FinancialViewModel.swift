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

    // What the last decision changed. Filled from the service's response, never recomputed here.
    var lastContribution: Contribution?
    var lastGoal: Goal?
    var milestoneCrossed: GoalMilestone?
    var latestPetState: PetState?

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
    /// `goalId` picks the goal a `save_instead` lands on. The service (`sendAction`) is the only thing that credits
    /// it, so this view model must never add a contribution itself, or the amount would be counted twice.
    func sendDecision(action: String, amount: Double = 25.00, goalId: String? = nil) async {
        guard !isSendingAction else { return }
        selectedAction = action
        decisionResult = nil
        lastContribution = nil
        lastGoal = nil
        milestoneCrossed = nil

        if action == "save_instead", goalId == nil {
            decisionResult = "Set a savings goal first so Mochi knows where this goes."
            return
        }

        isSendingAction = true
        let payload = FinancialAction(action: action, amount: amount, goalId: action == "save_instead" ? goalId : nil)
        do {
            let response = try await service.sendAction(petId: settings.activePetId, action: payload)
            decisionResult = response.message
            lastContribution = response.contribution
            lastGoal = response.goal
            milestoneCrossed = response.milestoneCrossed
            latestPetState = response.petState
        } catch {
            decisionResult = error.localizedDescription
        }
        isSendingAction = false
    }

    /// Progress of the credited goal just before the last save, for animating the result bar.
    var progressBeforeLastSave: Double? {
        guard let goal = lastGoal, let contribution = lastContribution else { return nil }
        return min(max((goal.current - contribution.amount) / max(goal.target, 0.01), 0), 1)
    }

    func clearDecisionResult() {
        decisionResult = nil
        selectedAction = nil
        lastContribution = nil
        lastGoal = nil
        milestoneCrossed = nil
    }
}
