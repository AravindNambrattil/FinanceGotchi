import SwiftUI

struct GoalRow: View {
    let goal: Goal
    var isPrimary = false

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: goal.symbol, fill: isPrimary ? Theme.teal : Theme.sage, size: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(goal.name)
                        .font(Theme.label)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if isPrimary { MellowPill(text: "Primary", fill: Theme.teal.opacity(0.6)) }
                    if goal.status == .done {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.indigo)
                            .accessibilityLabel("Completed")
                    }
                }
                MellowProgressBar(value: goal.progress, fill: Theme.indigo, track: Theme.indigo.opacity(0.14), height: 8)
                Text("\(Money.string(goal.current)) of \(Money.string(goal.target))")
                    .font(Theme.caption.monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(16)
        .mellowCard(elevated: true)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
