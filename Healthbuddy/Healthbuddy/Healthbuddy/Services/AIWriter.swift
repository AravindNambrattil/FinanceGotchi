import Foundation

/// A fact sent to the server's text writer. Numbers must use the naming convention documented in `files/ai.py`
/// (`*_usd` dollars, `*_pct` percentages, `*_days` / `*_weeks` / `*_count` counts) because the server checks every number
/// in the AI's answer against them.
enum AIFact: Encodable, Hashable {
    case text(String)
    case number(Double)

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s):   try c.encode(s)
        case .number(let n): try c.encode(n)
        }
    }

    var canonical: String {
        switch self {
        case .text(let s):   "s:\(s)"
        case .number(let n): "n:\(n)"
        }
    }
}

enum AITextKind: String {
    case decision, insight, goal
}

private struct AITextRequest: Encodable {
    let kind: String
    let facts: [String: AIFact]
}

private struct AITextResponse: Decodable {
    let text: String?
}

struct AIChatTurn: Encodable {
    let role: String   // "user" or "assistant"
    let text: String
}

private struct AIChatRequest: Encodable {
    let message: String
    let facts: [String: AIFact]
    let history: [AIChatTurn]
}

/// AI-written sentences for the app. Every surface has built-in text, so this only ever *adds* to the screen:
/// it returns nil when the server is slow or unreachable, or when the server rejected the answer. It works in demo mode
/// too (it only needs the server for the sentence, not for any of the app's data), so a decision can be tested
/// repeatedly without touching real money.
/// The model runs on our own server; it never decides anything or does any maths.
@MainActor
final class AIWriter {
    static let shared = AIWriter()

    fileprivate let api: APIClient
    fileprivate let settings: AppSettings
    private var cache: [String: String] = [:]

    init(api: APIClient = .shared, settings: AppSettings = .shared) {
        self.api = api
        self.settings = settings
    }

    func text(kind: AITextKind, facts: [String: AIFact]) async -> String? {
        guard !facts.isEmpty else { return nil }

        let key = kind.rawValue + "|" + facts.keys.sorted().map { "\($0)=\(facts[$0]!.canonical)" }.joined(separator: ";")
        if let hit = cache[key] { return hit }

        do {
            let response: AITextResponse = try await api.post(
                "/pets/\(settings.activePetId)/ai/text",
                body: AITextRequest(kind: kind.rawValue, facts: facts),
                baseURL: settings.baseURL,
                slow: true
            )
            guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            cache[key] = text
            return text
        } catch {
            return nil
        }
    }
}

extension AIWriter {
    /// Mochi's answer to a typed question, or nil when the server is slow, unreachable, or rejected the answer.
    /// Not cached: the same question can deserve a different answer after the conversation moves on.
    func chat(message: String, facts: [String: AIFact], history: [AIChatTurn]) async -> String? {
        do {
            let response: AITextResponse = try await api.post(
                "/pets/\(settings.activePetId)/ai/chat",
                body: AIChatRequest(message: message, facts: facts, history: history),
                baseURL: settings.baseURL,
                slow: true
            )
            guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        } catch {
            return nil
        }
    }
}

// MARK: - Building facts
extension Goal {
    /// Facts for goal advice. The summary says exactly what is true so the model has nothing to guess.
    var aiFacts: [String: AIFact] {
        var facts: [String: AIFact] = [
            "goal": .text(name),
            "goal_pct": .number(Double(progressPercent)),
            "goal_remaining_usd": .number(remaining.rounded()),
        ]
        var summary = "\(name) goal is \(progressPercent)% funded with \(Money.string(remaining.rounded())) to go"
        if let perWeek = requiredPerWeek, let days = daysRemaining {
            let weeks = max(1, Int((Double(days) / 7).rounded()))
            facts["weekly_needed_usd"] = .number(perWeek.rounded(.up))
            facts["left_weeks"] = .number(Double(weeks))
            summary += "; about \(Money.string(perWeek.rounded(.up))) a week finishes it in \(weeks) weeks."
        } else {
            summary += " and no deadline is set."
        }
        facts["summary"] = .text(summary)
        return facts
    }
}

extension Array where Element == Transaction {
    /// Facts for the Money-tab insight, or nil when there is nothing to describe.
    var aiInsightFacts: [String: AIFact]? {
        guard !isEmpty else { return nil }
        let spent = filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
        let saved = filter { $0.amount > 0 && $0.category == "savings" }.reduce(0) { $0 + $1.amount }

        var byCategory: [String: Double] = [:]
        for tx in self where tx.amount < 0 { byCategory[tx.category, default: 0] += abs(tx.amount) }
        let top = byCategory.max { $0.value < $1.value }

        var summary = "Recent activity: saved \(Money.string(saved)) and spent \(Money.string(spent)) across \(count) transactions"
        var facts: [String: AIFact] = [
            "spent_usd": .number(spent.rounded()),
            "saved_usd": .number(saved.rounded()),
            "transactions_count": .number(Double(count)),
        ]
        if let top {
            summary += "; \(top.key) was the biggest category."
            facts["top_category"] = .text(top.key)
            facts["top_category_usd"] = .number(top.value.rounded())
        } else {
            summary += "."
        }
        facts["summary"] = .text(summary)
        return facts
    }
}

extension PetState {
    /// Facts for chat. Only finished numbers from what the app is already showing; the model does no maths.
    /// `goal` is the primary goal (falls back to the pet's own goal); `transactions` is whatever activity is loaded.
    func aiChatFacts(goal: Goal?, transactions: [Transaction], health: HealthPayload? = nil, healthHasEnergyAndExercise: Bool = true) -> [String: AIFact] {
        var facts: [String: AIFact] = [
            "pet": .text(name),
            "mood": .text(moodExpression.rawValue),
            "streak_days": .number(Double(savingStreak)),
            "savings_pct": .number(savingsScore.rounded()),
            "balance_usd": .number(currentBalance.rounded()),
            "emergency_fund_usd": .number(emergencyFund.rounded()),
            "emergency_target_usd": .number(emergencyFundTarget.rounded()),
            "emergency_pct": .number((emergencyFund / max(emergencyFundTarget, 1) * 100).rounded(.down)),
        ]
        var summary = "\(name) is \(moodExpression.rawValue); \(savingStreak)-day saving streak"

        if let goal {
            facts["goal"] = .text(goal.name)
            facts["goal_pct"] = .number(Double(goal.progressPercent))
            facts["goal_saved_usd"] = .number(goal.current.rounded())
            facts["goal_target_usd"] = .number(goal.target.rounded())
            facts["goal_remaining_usd"] = .number(goal.remaining.rounded())
            if let perWeek = goal.requiredPerWeek, let days = goal.daysRemaining {
                facts["weekly_needed_usd"] = .number(perWeek.rounded(.up))
                facts["left_weeks"] = .number(Double(max(1, Int((Double(days) / 7).rounded()))))
            }
            summary += "; \(goal.name) goal \(goal.progressPercent)% funded"
        } else if let goal = self.goal {
            facts["goal"] = .text(goal.name)
            facts["goal_pct"] = .number(Double(goal.progressPercent))
            facts["goal_saved_usd"] = .number(goal.current.rounded())
            facts["goal_target_usd"] = .number(goal.target.rounded())
            facts["goal_remaining_usd"] = .number(max(goal.target - goal.current, 0).rounded())
            summary += "; \(goal.name) goal \(goal.progressPercent)% funded"
        }

        if let activity = transactions.aiInsightFacts {
            for key in ["spent_usd", "saved_usd", "transactions_count", "top_category", "top_category_usd"] {
                // Renamed so it is clear these are recent-activity numbers, not the goal's.
                if let value = activity[key] { facts["recent_" + key] = value }
            }
        }
        if let health {
            facts["steps_count"] = .number(Double(health.steps))
            if healthHasEnergyAndExercise {
                facts["active_energy_kcal_count"] = .number(health.activeEnergyKcal.rounded())
                facts["exercise_minutes_count"] = .number(Double(health.exerciseMinutes))
            }
            facts["energy_pct"] = .number(energy.rounded())
        }
        facts["summary"] = .text(summary + ".")
        return facts
    }
}
