import Foundation
import Observation

@Observable
@MainActor
final class FinancialViewModel {
    var transactions: [Transaction] = []
    var isLoading: Bool = false
    var errorMessage: String?

    /// The pending "Mochi wants..." prompt. Nil means there is nothing to decide right now.
    var offer: Offer?
    var offerError: String?

    // Decision state
    var isSendingAction: Bool = false
    var decisionResult: String?
    var selectedAction: String?

    // What the last decision changed. Filled from the service's response, never recomputed here.
    var lastContribution: Contribution?
    var lastGoal: Goal?
    var milestoneCrossed: GoalMilestone?
    var latestPetState: PetState?

    /// AI-written sentence about the last decision. It arrives a few seconds after the built-in message, or never.
    var aiMessage: String?
    /// AI-written summary of recent activity for the Money tab.
    var insight: String?
    @ObservationIgnored private var aiToken = UUID()
    @ObservationIgnored private var insightKey: String?

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
        Task { await loadInsight() }
    }

    // MARK: - AI insight
    func loadInsight() async {
        guard let facts = transactions.aiInsightFacts else {
            insight = nil
            return
        }
        let key = facts.keys.sorted().map { "\($0)=\(facts[$0]!.canonical)" }.joined(separator: ";")
        if key == insightKey, insight != nil { return }
        insightKey = key
        insight = await AIWriter.shared.text(kind: .insight, facts: facts)
    }

    // MARK: - Load Offer
    func loadOffer() async {
        do {
            offer = try await service.fetchOffer(petId: settings.activePetId)
            offerError = nil
        } catch {
            // Keep whatever offer we had; an outage must not look like "nothing to decide".
            offerError = error.localizedDescription
        }
    }

    // MARK: - Send Financial Decision
    /// `goalId` picks the goal a `save_instead` lands on. The service (`sendAction`) is the only thing that credits
    /// it, so this view model must never add a contribution itself, or the amount would be counted twice.
    func sendDecision(action: String, goalId: String? = nil) async {
        guard !isSendingAction, let offer else { return }
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
        let payload = FinancialAction(
            action: action,
            amount: offer.cost,
            goalId: action == "save_instead" ? goalId : nil,
            offerId: offer.id
        )
        do {
            let response = try await service.sendAction(petId: settings.activePetId, action: payload)
            decisionResult = response.message
            lastContribution = response.contribution
            lastGoal = response.goal
            milestoneCrossed = response.milestoneCrossed
            latestPetState = response.petState

            // Ask the AI for a sentence about this decision, without making the result card wait for it.
            let token = UUID()
            aiToken = token
            aiMessage = nil
            // Only for a save. For a purchase or a deferral the AI mostly repeated the facts back and carried the most
            // risk of judging, so those keep their built-in message.
            let facts = Self.decisionFacts(action: action, offer: offer, goal: response.goal)
            if !facts.isEmpty {
                Task { [weak self] in
                    let text = await AIWriter.shared.text(kind: .decision, facts: facts)
                    if let self, self.aiToken == token { self.aiMessage = text }
                }
            }

            await loadOffer()   // the server resolves the offer; ask what Mochi wants next
            await loadTransactions()
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

    /// What actually happened, in plain words plus checked numbers. The summary keeps the model from guessing.
    /// Empty means "don't ask the AI".
    private static func decisionFacts(action: String, offer: Offer, goal: Goal?) -> [String: AIFact] {
        let amount = Money.string(offer.cost)
        switch action {
        case "save_instead":
            guard let goal else { return [:] }
            return [
                "event": .text("save"),
                "summary": .text("Saved \(amount) for the \(goal.name) goal instead of buying \(offer.title)."),
                "amount_usd": .number(offer.cost),
                "goal": .text(goal.name),
                "goal_saved_usd": .number(goal.current.rounded()),
                "goal_target_usd": .number(goal.target.rounded()),
                "goal_pct": .number(Double(goal.progressPercent)),
                "goal_remaining_usd": .number(goal.remaining.rounded()),
            ]
        default:
            return [:]   // purchases and deferrals keep their built-in message
        }
    }

    func clearDecisionResult() {
        aiToken = UUID()
        aiMessage = nil
        decisionResult = nil
        selectedAction = nil
        lastContribution = nil
        lastGoal = nil
        milestoneCrossed = nil
    }
}
