import SwiftUI

struct DecisionView: View {
    var viewModel: FinancialViewModel
    var petVM: PetViewModel

    let scenario = (name: "Mochi wants new headphones", amount: 25.00)

    var body: some View {
        VStack(spacing: 20) {
            scenarioCard
            actionButtons
        }
        .overlay {
            if let result = viewModel.decisionResult {
                resultOverlay(message: result)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.decisionResult != nil)
    }

    // MARK: - Scenario Card
    private var scenarioCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.indigo.opacity(0.2), Color.purple.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                Text("💸")
                    .font(.system(size: 40))
            }

            VStack(spacing: 6) {
                Text(scenario.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(String(format: "$%.2f", scenario.amount))
                    .font(.system(size: 32, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.indigo.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            actionButton(label: "Buy It",     subtitle: "Spend $\(String(format: "%.2f", scenario.amount)) now",  action: "buy",          color: .red,    icon: "cart.fill")
            actionButton(label: "Save It",    subtitle: "Put it towards your goal instead",                      action: "save_instead", color: .green,  icon: "banknote.fill")
            actionButton(label: "Maybe Later", subtitle: "Defer the decision for now",                           action: "defer",        color: .orange, icon: "clock.fill")
        }
    }

    private func actionButton(label: String, subtitle: String, action: String, color: Color, icon: String) -> some View {
        let isSelected = viewModel.selectedAction == action
        let isDisabled = viewModel.isSendingAction

        return Button {
            Task { await viewModel.sendDecision(action: action, amount: scenario.amount) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? .white.opacity(0.25) : color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? .white : color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.75)
                }
                Spacer()

                if isSelected && viewModel.isSendingAction {
                    ProgressView().tint(isSelected ? .white : color)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color : color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? .clear : color.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundStyle(isSelected ? .white : color)
        }
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    // MARK: - Result Overlay
    private func resultOverlay(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("🎉")
                    .font(.system(size: 56))
                Text(message)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    viewModel.clearDecisionResult()
                    Task { await petVM.loadPetState() }
                } label: {
                    Text("Got it!")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.88).combined(with: .opacity))
        }
    }
}

#Preview {
    DecisionView(
        viewModel: FinancialViewModel(service: MockPetService()),
        petVM: .previewLoaded()
    )
    .padding()
}
