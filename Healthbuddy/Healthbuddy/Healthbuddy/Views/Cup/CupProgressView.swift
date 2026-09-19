import SwiftUI

struct GoalsView: View {
    var petVM: PetViewModel

    private var pet: PetState? { petVM.petState }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let pet {
                        savingsScoreCard(pet: pet)
                        if let goal = pet.goal {
                            goalProgressCard(goal: goal, pet: pet)
                        }
                        emergencyFundCard(pet: pet)
                        savingStreakCard(pet: pet)
                        tipsSection
                    } else {
                        ProgressView()
                            .scaleEffect(1.2)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .padding(.top, 8)
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { if petVM.petState == nil { await petVM.loadPetState() } }
    }

    // MARK: - Savings Score Card
    private func savingsScoreCard(pet: PetState) -> some View {
        VStack(spacing: 0) {
            // Top: score display
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(scoreColor(pet.savingsScore).opacity(0.2), lineWidth: 8)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: pet.savingsScore / 100)
                        .stroke(
                            LinearGradient(
                                colors: [scoreColor(pet.savingsScore).opacity(0.7), scoreColor(pet.savingsScore)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: pet.savingsScore)
                    VStack(spacing: 0) {
                        Text("\(Int(pet.savingsScore))")
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(scoreColor(pet.savingsScore))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Savings Health")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    HStack(spacing: 6) {
                        Text(scoreLabel(pet.savingsScore))
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(scoreColor(pet.savingsScore).opacity(0.15))
                            .foregroundStyle(scoreColor(pet.savingsScore))
                            .clipShape(Capsule())
                        if pet.savingStreak > 0 {
                            Label("\(pet.savingStreak) day streak", systemImage: "flame.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(scoreColor(pet.savingsScore).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(scoreColor(pet.savingsScore).opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Goal Progress Card
    private func goalProgressCard(goal: SavingsGoal, pet: PetState) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(goal.name)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.0f", goal.current))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.indigo)
                    Text(String(format: "of $%.0f", goal.target))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.indigo.opacity(0.12))
                            .frame(height: 14)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.indigo.opacity(0.7), Color.purple],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(geo.size.width * goal.progress, 14), height: 14)
                            .animation(.spring(response: 0.7, dampingFraction: 0.7), value: goal.progress)
                    }
                }
                .frame(height: 14)

                HStack {
                    Text("\(goal.progressPercent)% complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.0f to go", max(goal.target - goal.current, 0)))
                        .font(.caption.bold())
                        .foregroundStyle(.indigo)
                }
            }

            goalMilestoneView(progress: goal.progress)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private func goalMilestoneView(progress: Double) -> some View {
        let (emoji, title, subtitle): (String, String, String) = switch true {
        case progress >= 1.0:  ("🎉", "Goal reached!", "Mochi is throwing a party!")
        case progress >= 0.75: ("🤩", "Almost there!", "Mochi is buzzing with excitement.")
        case progress >= 0.50: ("😊", "Halfway milestone!", "Mochi unlocked a new accessory.")
        case progress >= 0.25: ("🌱", "Growing strong!", "Mochi cheers every step forward.")
        default:               ("💪", "Every save counts!", "Start the momentum — Mochi believes in you.")
        }

        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Emergency Fund
    private func emergencyFundCard(pet: PetState) -> some View {
        let progress = min(pet.emergencyFund / max(pet.emergencyFundTarget, 1), 1.0)
        let isHealthy = progress >= 0.5
        let color: Color = isHealthy ? .green : .orange

        return VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                        Image(systemName: "shield.fill")
                            .font(.subheadline)
                            .foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency Fund")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(isHealthy ? "Looking healthy" : "Still building")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(isHealthy ? "Healthy" : "Building")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.12)).frame(height: 10)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(geo.size.width * progress, 10), height: 10)
                            .animation(.spring(response: 0.6), value: progress)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text(String(format: "$%.0f saved", pet.emergencyFund))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(color)
                    Spacer()
                    Text(String(format: "Goal: $%.0f", pet.emergencyFundTarget))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Saving Streak Card
    private func savingStreakCard(pet: PetState) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(pet.savingStreak > 0
                          ? LinearGradient(colors: [.orange.opacity(0.7), .red.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 56, height: 56)
                Text(pet.savingStreak > 0 ? "🔥" : "💤")
                    .font(.system(size: 28))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Saving Streak")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(pet.savingStreak > 0
                     ? "\(pet.savingStreak) day\(pet.savingStreak == 1 ? "" : "s") and counting!"
                     : "Save today to start a streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if pet.savingStreak > 0 {
                Text("\(pet.savingStreak)")
                    .font(.system(size: 36, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Tips Section
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips from Mochi")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                tipCard(icon: "banknote.fill",         color: .green,  title: "Consistent Saving",     body: "Even small daily saves add up. Each one boosts your score and keeps Mochi happy.")
                tipCard(icon: "shield.fill",            color: .blue,   title: "Emergency Fund First",  body: "A buffer means unexpected expenses won't derail your goals — or stress out Mochi.")
                tipCard(icon: "scalemass.fill",         color: .purple, title: "Balance Needs & Wants", body: "Mochi doesn't judge spending — the goal is balance, not denial.")
                tipCard(icon: "clock.arrow.circlepath", color: .orange, title: "Patience Pays Off",     body: "Long-term goals feel slow, but every step forward is progress Mochi can feel.")
            }
        }
    }

    private func tipCard(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return .green
        case 50...: return .orange
        default:    return .red
        }
    }

    private func scoreLabel(_ score: Double) -> String {
        switch score {
        case 80...: return "Great"
        case 60...: return "Good"
        case 40...: return "Fair"
        default:    return "Needs Work"
        }
    }
}

#Preview {
    GoalsView(petVM: .previewLoaded())
}
