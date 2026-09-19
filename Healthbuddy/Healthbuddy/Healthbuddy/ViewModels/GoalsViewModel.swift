import Foundation
import Observation

@Observable
@MainActor
final class GoalsViewModel {
    var snapshot: GoalsSnapshot = .empty
    /// Contribution logs keyed by goal id, filled on demand by `loadContributions`.
    var contributions: [String: [Contribution]] = [:]
    var loadState: LoadState = .idle
    var errorMessage: String?
    /// Set when a contribution moves a goal into a higher band; the view shows a celebration and clears it.
    var celebration: GoalMilestone?

    @ObservationIgnored private let store: GoalStoreProtocol
    @ObservationIgnored private let settings: AppSettings

    init(store: GoalStoreProtocol? = nil, settings: AppSettings = .shared) {
        self.settings = settings
        self.store = store ?? GoalStoreFactory.make(settings: settings)
    }

    private var petId: String { settings.activePetId }

    // MARK: - Derived
    var trackedGoals: [Goal] { snapshot.trackedGoals }
    var primaryGoal: Goal? { snapshot.primaryGoal }
    var emergencyGoal: Goal? { snapshot.emergencyGoal }
    /// Goals that can still receive a save.
    var openGoals: [Goal] { trackedGoals.filter { $0.status == .active } }

    func goal(id: String) -> Goal? { snapshot.goals.first { $0.id == id } }

    // MARK: - Load
    func load() async {
        if snapshot.goals.isEmpty { loadState = .loading }
        do {
            snapshot = try await store.fetchSnapshot(petId: petId)
            loadState = .success
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Reload without showing a spinner, e.g. after a decision credited a goal elsewhere.
    func refresh() async {
        if let fresh = try? await store.fetchSnapshot(petId: petId) {
            snapshot = fresh
            loadState = .success
        }
    }

    func loadContributions(goalId: String) async {
        do {
            contributions[goalId] = try await store.fetchContributions(petId: petId, goalId: goalId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Goal CRUD
    @discardableResult
    func create(_ draft: GoalDraft) async -> Goal? {
        await perform { [self] in
            let goal = try await store.createGoal(petId: petId, draft: draft)
            snapshot = try await store.fetchSnapshot(petId: petId)
            return goal
        }
    }

    @discardableResult
    func update(goalId: String, draft: GoalDraft) async -> Goal? {
        await perform { [self] in
            let goal = try await store.updateGoal(petId: petId, goalId: goalId, draft: draft)
            snapshot = try await store.fetchSnapshot(petId: petId)
            return goal
        }
    }

    func setPrimary(goalId: String) async {
        let previous = snapshot
        snapshot.primaryGoalId = goalId      // optimistic; rolled back if the store refuses
        do {
            snapshot = try await store.setPrimaryGoal(petId: petId, goalId: goalId)
        } catch {
            snapshot = previous
            errorMessage = error.localizedDescription
        }
    }

    func archive(goalId: String) async {
        await perform { [self] in
            snapshot = try await store.removeGoal(petId: petId, goalId: goalId, hard: false)
        }
    }

    func delete(goalId: String) async {
        await perform { [self] in
            snapshot = try await store.removeGoal(petId: petId, goalId: goalId, hard: true)
            contributions[goalId] = nil
        }
    }

    // MARK: - Contributions
    /// Never optimistic: the new balance must come from the writer.
    @discardableResult
    func contribute(goalId: String, amount: Double, source: ContributionSource = .manual, note: String? = nil) async -> ContributionResult? {
        let result: ContributionResult? = await perform { [self] in
            let result = try await store.addContribution(
                petId: petId,
                goalId: goalId,
                draft: ContributionDraft(amount: amount, source: source, note: note)
            )
            snapshot = try await store.fetchSnapshot(petId: petId)
            contributions[goalId] = try await store.fetchContributions(petId: petId, goalId: goalId)
            return result
        }
        if let crossed = result?.milestoneCrossed { celebration = crossed }
        return result
    }

    func dismissCelebration() { celebration = nil }
    func clearError() { errorMessage = nil }

    // MARK: - Helpers
    @discardableResult
    private func perform<T>(_ work: () async throws -> T) async -> T? {
        errorMessage = nil
        do {
            return try await work()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Preview helper
extension GoalsViewModel {
    static func previewLoaded() -> GoalsViewModel {
        let vm = GoalsViewModel(store: LocalGoalStore.inMemory())
        Task { await vm.load() }
        return vm
    }
}
