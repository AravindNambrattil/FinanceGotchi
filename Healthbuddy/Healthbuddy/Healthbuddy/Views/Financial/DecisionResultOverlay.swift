import SwiftUI

/// Full-screen result of a financial decision. Lives above the tab bar (see `MainTabView`), so the dimming
/// covers the whole screen rather than just the decision card.
struct DecisionResultOverlay: View {
    var viewModel: FinancialViewModel
    var petVM: PetViewModel
    var goalsVM: GoalsViewModel

    var body: some View {
        if let message = viewModel.decisionResult {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    MochiView(
                        mood: viewModel.lastContribution != nil ? .excited : .happy,
                        milestone: viewModel.lastGoal?.milestone ?? .starting,
                        size: 96
                    )
                    Text(message)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let goal = viewModel.lastGoal, let before = viewModel.progressBeforeLastSave {
                        SaveResultBar(goal: goal, before: before, added: viewModel.lastContribution?.amount ?? 0)
                    }

                    Button(action: dismiss) {
                        Text("Got it!")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MellowFilledButtonStyle())
                    .padding(.horizontal, 32)
                }
                .padding(32)
                .mellowCard(Theme.surface, radius: 32)
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
                .padding(.horizontal, 24)
                .transition(.scale(scale: 0.88).combined(with: .opacity))

                if viewModel.milestoneCrossed != nil {
                    ConfettiView().ignoresSafeArea()
                }
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    private func dismiss() {
        let latest = viewModel.latestPetState
        viewModel.clearDecisionResult()
        if let latest {
            petVM.apply(latest)
        } else {
            Task { await petVM.loadPetState() }
        }
        Task { await goalsVM.refresh() }
    }
}

/// Goal bar that animates from its pre-save progress to the new one.
private struct SaveResultBar: View {
    let goal: Goal
    let before: Double
    let added: Double

    @State private var shown: Double

    init(goal: Goal, before: Double, added: Double) {
        self.goal = goal
        self.before = before
        self.added = added
        _shown = State(initialValue: before)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(goal.name, systemImage: goal.symbol)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                Spacer()
                Text("+" + Money.string(added))
                    .font(.system(.footnote, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.link)
            }
            .foregroundStyle(Theme.ink)

            MellowProgressBar(value: shown, fill: Theme.indigo, track: Theme.indigo.opacity(0.15), height: 12)

            HStack {
                Text("\(Money.string(goal.current)) of \(Money.string(goal.target))")
                Spacer()
                Text("\(goal.progressPercent)%")
            }
            .font(Theme.caption.monospacedDigit())
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 8)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.25)) {
                shown = goal.progress
            }
        }
        .accessibilityElement(children: .combine)
    }
}
