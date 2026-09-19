import SwiftUI

struct PetView: View {
    var petVM: PetViewModel
    var healthVM: HealthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    switch petVM.loadState {
                    case .loading:
                        loadingView
                    case .failure(let msg):
                        offlineBanner(message: msg)
                            .padding()
                    case .idle, .success:
                        if let pet = petVM.petState {
                            heroSection(pet: pet)
                            VStack(spacing: 16) {
                                statsCard(pet: pet)
                                financialSnapshotCard(pet: pet)
                                HealthActivityCard(viewModel: healthVM, petId: pet.petId)
                                if let companion = petVM.companionPet {
                                    companionCard(companion: companion)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("FinanceGotchi")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    mockBadge
                }
            }
            .refreshable {
                await petVM.retry()
            }
        }
        .reactionOverlay(message: petVM.reactionMessage, onDismiss: petVM.dismissReaction)
        .task {
            async let pet: () = petVM.loadPetState()
            async let companion: () = petVM.loadCompanionPet()
            async let health: () = healthVM.requestAuthorization()
            _ = await (pet, companion, health)
        }
    }

    // MARK: - Hero Section
    private func heroSection(pet: PetState) -> some View {
        ZStack(alignment: .bottom) {
            // Background gradient
            LinearGradient(
                colors: heroColors(mood: pet.moodExpression),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 300)

            // Subtle pattern overlay
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 240, height: 240)
                .offset(x: 100, y: -80)
            Circle()
                .fill(.white.opacity(0.04))
                .frame(width: 160, height: 160)
                .offset(x: -90, y: -20)

            VStack(spacing: 10) {
                // Avatar bubble
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 130, height: 130)
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 110, height: 110)
                    Text(moodEmoji(mood: pet.moodExpression))
                        .font(.system(size: 64))
                }

                Text(pet.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(pet.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - Stats Card
    private func statsCard(pet: PetState) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Wellbeing")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                moodPill(mood: pet.moodExpression)
            }

            VStack(spacing: 12) {
                statRow(label: "Needs",   value: pet.needs,        color: .orange, icon: "heart.fill")
                statRow(label: "Energy",  value: pet.energy,       color: .blue,   icon: "bolt.fill")
                statRow(label: "Savings", value: pet.savingsScore, color: .green,  icon: "banknote.fill")
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private func statRow(label: String, value: Double, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (value / 100), height: 8)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: value)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Financial Snapshot
    private func financialSnapshotCard(pet: PetState) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Financial Snapshot")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            HStack(spacing: 1) {
                snapshotCell(
                    title: "Balance",
                    value: String(format: "$%.0f", pet.currentBalance),
                    icon: "dollarsign.circle.fill",
                    color: .green
                )
                snapshotDivider
                snapshotCell(
                    title: "Emergency",
                    value: String(format: "$%.0f", pet.emergencyFund),
                    icon: "shield.fill",
                    color: .blue
                )
                snapshotDivider
                if let goal = pet.goal {
                    snapshotCell(
                        title: goal.name,
                        value: String(format: "$%.0f", goal.current),
                        icon: "star.fill",
                        color: .purple
                    )
                } else {
                    snapshotCell(title: "Goal", value: "Set one!", icon: "plus.circle.fill", color: .secondary)
                }
            }
            .padding(.bottom, 20)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private var snapshotDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 48)
    }

    private func snapshotCell(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Companion Card
    private func companionCard(companion: PetState) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: heroColors(mood: companion.moodExpression),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 52, height: 52)
                Text(moodEmoji(mood: companion.moodExpression))
                    .font(.system(size: 28))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(companion.name) is here!")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(companion.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Task { await petVM.interactWithCompanion() }
            } label: {
                Text("Hang Out")
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Fetching Mochi...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Offline Banner
    private func offlineBanner(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Can't reach Mochi right now.")
                .font(.headline)
            Text("Check your Wi-Fi connection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await petVM.retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding()
    }

    // MARK: - Mock Badge
    @ViewBuilder
    private var mockBadge: some View {
        if AppSettings.shared.useMockData {
            Text("MOCK")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.25))
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }

    // MARK: - Mood Pill
    private func moodPill(mood: PetState.MoodExpression) -> some View {
        let (label, color): (String, Color) = switch mood {
        case .happy:   ("Happy", .yellow)
        case .excited: ("Excited", .pink)
        case .neutral: ("Okay", .gray)
        case .sad:     ("Sad", .blue)
        }
        return Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Helpers
    private func moodEmoji(mood: PetState.MoodExpression) -> String {
        switch mood {
        case .happy:   return "😊"
        case .sad:     return "😢"
        case .neutral: return "😐"
        case .excited: return "🤩"
        }
    }

    private func heroColors(mood: PetState.MoodExpression) -> [Color] {
        switch mood {
        case .happy:   return [Color(red: 0.98, green: 0.72, blue: 0.25), Color(red: 0.98, green: 0.48, blue: 0.22)]
        case .sad:     return [Color(red: 0.3, green: 0.45, blue: 0.9), Color(red: 0.2, green: 0.3, blue: 0.75)]
        case .neutral: return [Color(red: 0.5, green: 0.55, blue: 0.65), Color(red: 0.38, green: 0.42, blue: 0.52)]
        case .excited: return [Color(red: 0.85, green: 0.3, blue: 0.75), Color(red: 0.55, green: 0.2, blue: 0.9)]
        }
    }
}

#Preview {
    PetView(petVM: .previewLoaded(), healthVM: HealthViewModel())
}
