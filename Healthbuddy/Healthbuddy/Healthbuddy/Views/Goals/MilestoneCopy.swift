import Foundation

/// Mochi's voice for each goal band. Copy lives here in the view layer; the band itself comes from `Goal.milestone`.
extension GoalMilestone {
    var title: String {
        switch self {
        case .starting: "Every save counts!"
        case .growing:  "Growing strong!"
        case .halfway:  "Halfway there!"
        case .almost:   "Almost there!"
        case .reached:  "Goal reached!"
        }
    }

    var subtitle: String {
        switch self {
        case .starting: "Start the momentum. Mochi believes in you."
        case .growing:  "Mochi is wearing a leaf to celebrate."
        case .halfway:  "Mochi picked up a cozy scarf."
        case .almost:   "Mochi is sparkling with excitement."
        case .reached:  "Mochi is throwing a party!"
        }
    }
}

extension Goal {
    /// Encouraging pace line. Nil when there is nothing useful to say.
    var paceText: String? {
        if isComplete { return "Fully funded. Nicely done!" }
        guard let deadline else { return nil }
        if isPastDeadline { return "Deadline passed. No rush, keep going." }
        if daysRemaining == 0 { return "Due today with \(Money.string(remaining)) to go." }
        guard let perWeek = requiredPerWeek else { return nil }
        let date = deadline.formatted(.dateTime.month(.abbreviated).day())
        return "About \(Money.string(perWeek.rounded(.up))) a week to finish by \(date)."
    }
}
