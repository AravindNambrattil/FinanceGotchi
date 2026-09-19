import Foundation

// MARK: - Errors
enum GoalStoreError: LocalizedError {
    case goalNotFound
    case invalidAmount
    case insufficientFunds
    case hasContributions

    var errorDescription: String? {
        switch self {
        case .goalNotFound:      "That goal couldn't be found."
        case .invalidAmount:     "Enter an amount greater than zero."
        case .insufficientFunds: "That's more than is saved in this goal."
        case .hasContributions:  "This goal has contributions, so it can only be archived."
        }
    }
}

// MARK: - Protocol
/// Goals are financial state, so the backend will own them. This protocol is the seam: `LocalGoalStore` backs
/// the app until the endpoints in CLAUDE.md ship, then `RemoteGoalStore` takes over with no UI changes.
///
/// A goal's `current` only ever moves through `addContribution`.
protocol GoalStoreProtocol {
    func fetchSnapshot(petId: String) async throws -> GoalsSnapshot
    func createGoal(petId: String, draft: GoalDraft) async throws -> Goal
    func updateGoal(petId: String, goalId: String, draft: GoalDraft) async throws -> Goal
    /// Archives by default. `hard` deletes, and is refused for a goal with real contributions.
    func removeGoal(petId: String, goalId: String, hard: Bool) async throws -> GoalsSnapshot
    func setPrimaryGoal(petId: String, goalId: String) async throws -> GoalsSnapshot
    func fetchContributions(petId: String, goalId: String) async throws -> [Contribution]
    func addContribution(petId: String, goalId: String, draft: ContributionDraft) async throws -> ContributionResult
}

// MARK: - Factory
enum GoalStoreFactory {
    /// One shared instance: each view model builds its own service, and they must all see the same goals.
    private static let local = LocalGoalStore.persistent()

    static func make(settings: AppSettings = .shared) -> GoalStoreProtocol {
        settings.useMockData ? local : RemoteGoalStore(settings: settings)
    }
}

// MARK: - Local store
/// Holds goals and their contribution log, persisted as JSON in Application Support (or kept in memory for
/// previews). The stored bytes match the API shape, so swapping to `RemoteGoalStore` needs no model changes.
final class LocalGoalStore: GoalStoreProtocol {
    fileprivate struct Envelope: Codable {
        var snapshot: GoalsSnapshot
        var contributions: [Contribution]
    }

    private let directory: URL?
    private var cache: [String: Envelope] = [:]

    /// `directory == nil` keeps everything in memory.
    init(directory: URL?) {
        self.directory = directory
    }

    static func persistent() -> LocalGoalStore {
        LocalGoalStore(directory: URL.applicationSupportDirectory)
    }

    /// For `#Preview`s and tests, so they never touch the user's real goals.
    static func inMemory() -> LocalGoalStore {
        LocalGoalStore(directory: nil)
    }

    // MARK: Reads
    func fetchSnapshot(petId: String) async throws -> GoalsSnapshot {
        load(petId: petId).snapshot
    }

    func fetchContributions(petId: String, goalId: String) async throws -> [Contribution] {
        load(petId: petId).contributions
            .filter { $0.goalId == goalId }
            .sorted { $0.date > $1.date }
    }

    // MARK: Goal CRUD
    func createGoal(petId: String, draft: GoalDraft) async throws -> Goal {
        var env = load(petId: petId)
        let goal = Goal(
            kind: draft.kind,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: draft.symbol,
            target: Self.cents(draft.target),
            deadline: draft.deadline
        )
        env.snapshot.goals.append(goal)
        if env.snapshot.primaryGoal == nil || env.snapshot.trackedGoals.count == 1 {
            env.snapshot.primaryGoalId = goal.id
        }
        try save(env, petId: petId)
        return goal
    }

    func updateGoal(petId: String, goalId: String, draft: GoalDraft) async throws -> Goal {
        var env = load(petId: petId)
        guard let index = env.snapshot.goals.firstIndex(where: { $0.id == goalId }) else {
            throw GoalStoreError.goalNotFound
        }
        env.snapshot.goals[index].name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        env.snapshot.goals[index].symbol = draft.symbol
        env.snapshot.goals[index].target = Self.cents(draft.target)
        env.snapshot.goals[index].deadline = draft.deadline
        Self.refreshStatus(&env.snapshot.goals[index])
        try save(env, petId: petId)
        return env.snapshot.goals[index]
    }

    func removeGoal(petId: String, goalId: String, hard: Bool) async throws -> GoalsSnapshot {
        var env = load(petId: petId)
        guard let index = env.snapshot.goals.firstIndex(where: { $0.id == goalId }) else {
            throw GoalStoreError.goalNotFound
        }

        if hard {
            let hasRealContributions = env.contributions.contains { $0.goalId == goalId && $0.source != .seed }
            if hasRealContributions { throw GoalStoreError.hasContributions }
            env.snapshot.goals.remove(at: index)
            env.contributions.removeAll { $0.goalId == goalId }
        } else {
            env.snapshot.goals[index].status = .archived
        }

        if env.snapshot.primaryGoalId == goalId {
            env.snapshot.primaryGoalId = Self.bestPrimaryCandidate(in: env.snapshot)?.id
        }
        try save(env, petId: petId)
        return env.snapshot
    }

    func setPrimaryGoal(petId: String, goalId: String) async throws -> GoalsSnapshot {
        var env = load(petId: petId)
        guard env.snapshot.trackedGoals.contains(where: { $0.id == goalId }) else {
            throw GoalStoreError.goalNotFound
        }
        env.snapshot.primaryGoalId = goalId
        try save(env, petId: petId)
        return env.snapshot
    }

    // MARK: Contributions
    func addContribution(petId: String, goalId: String, draft: ContributionDraft) async throws -> ContributionResult {
        let amount = Self.cents(draft.amount)
        guard amount != 0 else { throw GoalStoreError.invalidAmount }

        var env = load(petId: petId)
        guard let index = env.snapshot.goals.firstIndex(where: { $0.id == goalId }) else {
            throw GoalStoreError.goalNotFound
        }

        let before = env.snapshot.goals[index]
        let newCurrent = Self.cents(before.current + amount)
        guard newCurrent >= 0 else { throw GoalStoreError.insufficientFunds }

        let contribution = Contribution(
            goalId: goalId,
            amount: amount,
            date: draft.date,
            source: draft.source,
            note: draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        env.contributions.append(contribution)

        // The log is the source of truth: `current` is recomputed from it, never edited on its own.
        env.snapshot.goals[index].current = Self.sum(of: env.contributions, goalId: goalId)
        Self.refreshStatus(&env.snapshot.goals[index])
        assert(env.snapshot.goals[index].current == newCurrent, "goal balance drifted from its contribution log")

        let after = env.snapshot.goals[index]
        let crossed: GoalMilestone? = amount > 0 && after.milestone > before.milestone ? after.milestone : nil

        try save(env, petId: petId)
        return ContributionResult(
            contribution: contribution,
            goal: after,
            milestoneCrossed: crossed,
            message: Self.message(for: after, crossed: crossed)
        )
    }

    // MARK: Debug
    /// Wipes stored goals for a pet and reseeds them. Handy between demo runs.
    func resetToSeed(petId: String) throws {
        try save(Self.seed(petId: petId), petId: petId)
    }

    // MARK: Persistence
    private func fileURL(petId: String) -> URL? {
        directory?.appending(path: "goals-\(petId).json")
    }

    private func load(petId: String) -> Envelope {
        if let cached = cache[petId] { return cached }

        if let url = fileURL(petId: petId),
           let data = try? Data(contentsOf: url),
           let stored = try? JSONCoding.makeDecoder().decode(Envelope.self, from: data) {
            cache[petId] = stored
            return stored
        }

        let seeded = Self.seed(petId: petId)
        try? save(seeded, petId: petId)
        return seeded
    }

    private func save(_ env: Envelope, petId: String) throws {
        cache[petId] = env
        guard let url = fileURL(petId: petId) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONCoding.makeEncoder(pretty: true).encode(env)
        try data.write(to: url, options: .atomic)
    }

    // MARK: Rules that the backend will own
    // BACKEND OWNS THIS: completing a goal and the pet's reaction are financial policy (db.apply_decision).
    // These are stand-ins so the local demo behaves like the real thing.
    private static func refreshStatus(_ goal: inout Goal) {
        guard goal.status != .archived else { return }
        goal.status = goal.current >= goal.target ? .done : .active
    }

    private static func message(for goal: Goal, crossed: GoalMilestone?) -> String {
        switch crossed {
        case .reached:  return "You did it! \(goal.name) is fully funded."
        case .almost:   return "Almost there! \(goal.name) is at \(goal.progressPercent)%."
        case .halfway:  return "Halfway to \(goal.name)! Mochi is thrilled."
        case .growing:  return "Nice start on \(goal.name). Keep it going!"
        default:        return "Nice! You're closer to your \(goal.name) goal."
        }
    }

    private static func bestPrimaryCandidate(in snapshot: GoalsSnapshot) -> Goal? {
        snapshot.trackedGoals
            .filter { $0.status == .active }
            .max { $0.progress < $1.progress }
    }

    // MARK: Helpers
    private static func cents(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func sum(of contributions: [Contribution], goalId: String) -> Double {
        cents(contributions.filter { $0.goalId == goalId }.reduce(0) { $0 + $1.amount })
    }
}

// MARK: - Seed data
extension LocalGoalStore {
    /// Believable demo data so the tracker never opens empty. Dates are relative to first launch, so the
    /// demo doesn't look stale. Each goal's contributions sum exactly to its `current`.
    fileprivate static func seed(petId: String) -> Envelope {
        let cal = Calendar.current
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: .now) ?? .now }
        func daysAhead(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: .now) ?? .now }

        struct Row { let daysAgo: Int; let amount: Double; let source: ContributionSource; let note: String }

        func build(
            id: String, kind: GoalKind, name: String, symbol: String, target: Double,
            deadline: Date?, createdDaysAgo: Int, rows: [Row]
        ) -> (Goal, [Contribution]) {
            let contributions = rows.map {
                Contribution(goalId: id, amount: $0.amount, date: daysAgo($0.daysAgo), source: $0.source, note: $0.note)
            }
            let goal = Goal(
                id: id, kind: kind, name: name, symbol: symbol,
                current: cents(contributions.reduce(0) { $0 + $1.amount }),
                target: target, deadline: deadline, createdAt: daysAgo(createdDaysAgo)
            )
            return (goal, contributions)
        }

        let emergency = build(
            id: "seed-emergency", kind: .emergency, name: "Emergency Fund", symbol: "shield.fill", target: 500,
            deadline: nil, createdDaysAgo: 45,
            rows: [Row(daysAgo: 45, amount: petId == "byte" ? 80 : 110, source: .seed, note: "Starting balance")]
        )

        let primary: (Goal, [Contribution])
        let secondary: (Goal, [Contribution])

        if petId == "byte" {
            primary = build(
                id: "seed-vacation", kind: .custom, name: "Vacation", symbol: "airplane.departure", target: 800,
                deadline: daysAhead(120), createdDaysAgo: 30,
                rows: [
                    Row(daysAgo: 30, amount: 300, source: .seed, note: "Starting balance"),
                    Row(daysAgo: 8, amount: 50, source: .manual, note: "Birthday money"),
                ]
            )
            secondary = build(
                id: "seed-laptop", kind: .custom, name: "Laptop", symbol: "laptopcomputer", target: 1000,
                deadline: nil, createdDaysAgo: 20,
                rows: [Row(daysAgo: 20, amount: 210, source: .seed, note: "Starting balance")]
            )
        } else {
            primary = build(
                id: "seed-laptop", kind: .custom, name: "Laptop", symbol: "laptopcomputer", target: 1000,
                deadline: daysAhead(90), createdDaysAgo: 45,
                rows: [
                    Row(daysAgo: 45, amount: 625, source: .seed, note: "Starting balance"),
                    Row(daysAgo: 12, amount: 20, source: .manual, note: "Skipped takeout"),
                    Row(daysAgo: 6, amount: 25, source: .savedInstead, note: "Skipped headphones"),
                    Row(daysAgo: 3, amount: 30, source: .manual, note: "Payday transfer"),
                    Row(daysAgo: 1, amount: 20, source: .savedInstead, note: "Walked instead of rideshare"),
                ]
            )
            secondary = build(
                id: "seed-vacation", kind: .custom, name: "Vacation", symbol: "airplane.departure", target: 800,
                deadline: nil, createdDaysAgo: 30,
                rows: [
                    Row(daysAgo: 30, amount: 300, source: .seed, note: "Starting balance"),
                    Row(daysAgo: 8, amount: 50, source: .manual, note: "Birthday money"),
                ]
            )
        }

        return Envelope(
            snapshot: GoalsSnapshot(
                goals: [primary.0, secondary.0, emergency.0],
                primaryGoalId: primary.0.id
            ),
            contributions: primary.1 + secondary.1 + emergency.1
        )
    }
}

// MARK: - Remote store
/// Talks to the endpoints documented in CLAUDE.md ("Backend contract for goals"). Not exercised until the
/// backend ships them and `AppSettings.useMockData` is turned off.
final class RemoteGoalStore: GoalStoreProtocol {
    private struct Empty: Encodable {}

    private let api: APIClient
    private let settings: AppSettings

    init(api: APIClient = .shared, settings: AppSettings = .shared) {
        self.api = api
        self.settings = settings
    }

    func fetchSnapshot(petId: String) async throws -> GoalsSnapshot {
        try await api.get("/pets/\(petId)/goals", baseURL: settings.baseURL)
    }

    func createGoal(petId: String, draft: GoalDraft) async throws -> Goal {
        try await api.post("/pets/\(petId)/goals", body: draft, baseURL: settings.baseURL)
    }

    func updateGoal(petId: String, goalId: String, draft: GoalDraft) async throws -> Goal {
        try await api.put("/pets/\(petId)/goals/\(goalId)", body: draft, baseURL: settings.baseURL)
    }

    func removeGoal(petId: String, goalId: String, hard: Bool) async throws -> GoalsSnapshot {
        try await api.delete(
            "/pets/\(petId)/goals/\(goalId)",
            query: [URLQueryItem(name: "hard", value: hard ? "true" : "false")],
            baseURL: settings.baseURL
        )
    }

    func setPrimaryGoal(petId: String, goalId: String) async throws -> GoalsSnapshot {
        try await api.post("/pets/\(petId)/goals/\(goalId)/primary", body: Empty(), baseURL: settings.baseURL)
    }

    func fetchContributions(petId: String, goalId: String) async throws -> [Contribution] {
        try await api.get("/pets/\(petId)/goals/\(goalId)/contributions", baseURL: settings.baseURL)
    }

    func addContribution(petId: String, goalId: String, draft: ContributionDraft) async throws -> ContributionResult {
        try await api.post("/pets/\(petId)/goals/\(goalId)/contributions", body: draft, baseURL: settings.baseURL)
    }
}

// MARK: - Small helpers
private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
