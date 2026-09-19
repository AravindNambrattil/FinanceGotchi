import SwiftUI

struct DecisionView: View {
    var viewModel: FinancialViewModel
    var petVM: PetViewModel
    var goalsVM: GoalsViewModel

    let scenario = (name: "Mochi wants new headphones", amount: 25.00)

    /// Goal the user picked to receive a save. Falls back to the primary goal.
    @State private var saveTargetId: String?

    private var saveTarget: Goal? {
        goalsVM.openGoals.first { $0.id == saveTargetId }
            ?? goalsVM.primaryGoal.flatMap { $0.status == .active ? $0 : nil }
            ?? goalsVM.openGoals.first
    }

    var body: some View {
        VStack(spacing: 16) {
            scenarioCard
            if goalsVM.openGoals.count > 1 { targetPicker }
            actionButtons
        }
        .sensoryFeedback(trigger: viewModel.lastContribution?.id) { _, new in new != nil ? .success : nil }
        .task { await goalsVM.load() }
    }

    // MARK: - Scenario Card
    private var scenarioCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(.white.opacity(0.6), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.name)
                    .font(.system(.headline, design: .rounded))
                Text(String(format: "$%.2f", scenario.amount))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.navy)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.onPastel)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mellowCard(Theme.yellow)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Save target
    private var targetPicker: some View {
        HStack {
            Text("If you save it, it goes to")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 8)
            Menu {
                ForEach(goalsVM.openGoals) { goal in
                    Button {
                        saveTargetId = goal.id
                    } label: {
                        Label(goal.name, systemImage: saveTarget?.id == goal.id ? "checkmark" : goal.symbol)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: saveTarget?.symbol ?? "star.fill")
                    Text(saveTarget?.name ?? "Pick a goal")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.onPastel)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.teal.opacity(0.6), in: Capsule())
            }
            .accessibilityLabel("Goal to save into")
            .accessibilityValue(saveTarget?.name ?? "None")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            actionButton(label: "Buy It",      subtitle: "Spend $\(String(format: "%.2f", scenario.amount)) now",           action: "buy",          color: Theme.coral, icon: "cart.fill")
            actionButton(label: "Save It",     subtitle: saveSubtitle,                                                       action: "save_instead", color: Theme.teal,  icon: "banknote.fill")
            actionButton(label: "Maybe Later", subtitle: "Defer the decision for now",                                        action: "defer",        color: Theme.sage,  icon: "clock.fill")
        }
    }

    private var saveSubtitle: String {
        if let goal = saveTarget { return "Put it towards \(goal.name) instead" }
        return "Create a goal first"
    }

    private func actionButton(label: String, subtitle: String, action: String, color: Color, icon: String) -> some View {
        let isSelected = viewModel.selectedAction == action
        let isDisabled = viewModel.isSendingAction

        return Button {
            Task {
                await viewModel.sendDecision(
                    action: action,
                    amount: scenario.amount,
                    goalId: action == "save_instead" ? saveTarget?.id : nil
                )
            }
        } label: {
            HStack(spacing: 14) {
                IconTile(systemImage: icon, fill: isSelected ? .white.opacity(0.9) : color, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text(subtitle)
                        .font(Theme.caption)
                        .opacity(0.75)
                }
                Spacer()

                if isSelected && viewModel.isSendingAction {
                    ProgressView().tint(isSelected ? .white : Theme.onPastel)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? Color.white : Theme.onPastel)
            .background(
                isSelected ? Theme.navy : color.opacity(0.28),
                in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

#Preview {
    DecisionView(
        viewModel: FinancialViewModel(service: MockPetService()),
        petVM: .previewLoaded(),
        goalsVM: .previewLoaded()
    )
    .padding()
}
