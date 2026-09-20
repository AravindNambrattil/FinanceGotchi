import SwiftUI

struct PetView: View {
    var petVM: PetViewModel
    var healthVM: HealthViewModel
    /// Called by the "See all" link; the parent switches to the Goals tab.
    var onSeeAll: () -> Void = {}
    /// Called by the "Chat with Mochi" card; the parent presents the chat sheet.
    var onChat: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch petVM.loadState {
                    case .loading:
                        loadingView
                    case .failure(let msg):
                        offlineBanner(message: msg)
                    case .idle, .success:
                        if let pet = petVM.petState {
                            topBar(pet: pet)
                            ScreenHeader(title: "Hi, I'm \(pet.name)", subtitle: pet.message)
                            heroStage(pet: pet)
                            chatCard(pet: pet)
                            deviceCard
                            moodCard(pet: pet)
                            workOnSection(pet: pet)
                            if let companion = petVM.companionPet {
                                companionCard(companion: companion)
                            }
                            HealthActivityCard(viewModel: healthVM, petId: pet.petId)
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await petVM.retry()
            }
        }
        .reactionOverlay(message: petVM.reactionMessage, onDismiss: petVM.dismissReaction)
        // Check whether the physical pet is online every few seconds while this tab is showing.
        .task(id: AppSettings.shared.useMockData) {
            while !Task.isCancelled {
                await petVM.refreshDevice()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task {
            async let pet: () = petVM.loadPetState()
            async let companion: () = petVM.loadCompanionPet()
            async let health: () = healthVM.requestAuthorization()
            _ = await (pet, companion, health)
        }
    }

    // MARK: - Top Bar
    private func topBar(pet: PetState) -> some View {
        HStack(spacing: 10) {
            Text("Mochi")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))

            Spacer()

            mockBadge

            MochiView(name: pet.name, mood: pet.moodExpression, size: 32, animated: false)
                .frame(width: 44, height: 44)
                .background(Theme.periwinkle.opacity(0.35), in: Circle())
        }
    }

    // MARK: - Hero
    /// Mochi on a soft stage. The decorations Mochi wears follow the primary goal's progress.
    private func heroStage(pet: PetState) -> some View {
        ZStack {
            Circle()
                .fill(Theme.periwinkle.opacity(0.22))
                .frame(width: 230, height: 230)
            Circle()
                .fill(Theme.yellow.opacity(0.55))
                .frame(width: 54, height: 54)
                .offset(x: -110, y: -70)
            Circle()
                .fill(Theme.teal.opacity(0.5))
                .frame(width: 36, height: 36)
                .offset(x: 118, y: 60)
            Image(systemName: "camera.macro")
                .font(.system(size: 30))
                .foregroundStyle(Theme.pink)
                .rotationEffect(.degrees(14))
                .offset(x: 112, y: -78)
                .accessibilityHidden(true)

            MochiView(
                name: pet.name,
                mood: pet.moodExpression,
                milestone: GoalMilestone(progress: pet.goal?.progress ?? 0),
                size: 170
            )
            .offset(y: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
    }

    // MARK: - Chat
    private func chatCard(pet: PetState) -> some View {
        Button(action: onChat) {
            HStack(spacing: 12) {
                IconTile(systemImage: "bubble.left.and.text.bubble.right.fill", fill: Theme.sky.opacity(0.7), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat with \(pet.name)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.ink)
                    Text("Ask about saving, health or your day")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .mellowCard(elevated: true)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Physical pet
    private var deviceCard: some View {
        let status = petVM.deviceStatus
        let online = status?.connected == true
        return HStack(spacing: 12) {
            Circle()
                .fill(online ? Theme.teal : Theme.lavender)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Physical Mochi")
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                Text(status?.summary ?? "Checking...")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: online ? "wifi" : "wifi.slash")
                .foregroundStyle(online ? Theme.indigo : Theme.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .mellowCard(elevated: true)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mood Card
    private func moodCard(pet: PetState) -> some View {
        HStack(alignment: .top, spacing: 6) {
            StatBubble(value: pet.moodExpression.label, label: "Mood") {
                MochiView(name: pet.name, mood: pet.moodExpression, size: 44, animated: false)
                    .offset(y: 1)
            }
            StatBubble(value: "\(Int(pet.needs))%", label: "Needs", ring: pet.needs / 100) {
                Image(systemName: "heart.fill").font(.system(size: 22))
            }
            StatBubble(value: "\(Int(pet.savingsScore))%", label: "Savings", ring: pet.savingsScore / 100) {
                Image(systemName: "banknote.fill").font(.system(size: 22))
            }
            StatBubble(value: "\(Int(pet.energy))%", label: "Energy", ring: pet.energy / 100) {
                Image(systemName: "bolt.fill").font(.system(size: 22))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .mellowCard(Theme.lime)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "camera.macro")
                .font(.system(size: 40))
                .foregroundStyle(Theme.pink)
                .rotationEffect(.degrees(-12))
                .offset(x: 8, y: -20)
                .accessibilityHidden(true)
        }
    }

    // MARK: - What Mochi is working on
    private func workOnSection(pet: PetState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MellowSectionHeader(
                title: "What is \(pet.name) working on?",
                actionTitle: "See all",
                action: onSeeAll
            )

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    goalTile(pet: pet)
                    PastelTile(
                        title: "Balance",
                        value: Money.string(pet.currentBalance),
                        caption: "Checking",
                        systemImage: "dollarsign.circle.fill",
                        fill: Theme.coral
                    )
                }
                VStack(spacing: 12) {
                    PastelTile(
                        title: "Saving streak",
                        value: "\(pet.savingStreak) day\(pet.savingStreak == 1 ? "" : "s")",
                        caption: pet.savingStreak > 0 ? "Keep it going" : "Save today to start",
                        systemImage: "flame.fill",
                        fill: Theme.yellow
                    )
                    PastelTile(
                        title: "Emergency fund",
                        value: Money.string(pet.emergencyFund),
                        caption: "of \(Money.string(pet.emergencyFundTarget))",
                        systemImage: "shield.fill",
                        fill: Theme.periwinkle,
                        progress: pet.emergencyFund / max(pet.emergencyFundTarget, 1),
                        minHeight: 190
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func goalTile(pet: PetState) -> some View {
        if let goal = pet.goal {
            PastelTile(
                title: "\(goal.name) goal",
                value: Money.string(goal.current),
                caption: "of \(Money.string(goal.target)) · \(goal.progressPercent)%",
                systemImage: "star.fill",
                fill: Theme.teal,
                progress: goal.progress,
                minHeight: 190
            )
        } else {
            PastelTile(
                title: "Goal",
                value: "Set one!",
                systemImage: "plus.circle.fill",
                fill: Theme.teal,
                minHeight: 190
            )
        }
    }

    // MARK: - Companion Card
    private func companionCard(companion: PetState) -> some View {
        HStack(spacing: 14) {
            MochiView(name: companion.name, mood: companion.moodExpression, size: 40, animated: false, tint: Theme.lavender)
                .frame(width: 56, height: 56)
                .background(Theme.pink.opacity(0.45), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("\(companion.name) is here!")
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                Text(companion.message)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Hang Out") {
                Task { await petVM.interactWithCompanion() }
            }
            .buttonStyle(MellowFilledButtonStyle())
        }
        .padding(16)
        .mellowCard(elevated: true)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Fetching Mochi...")
                .font(Theme.section)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Offline Banner
    private func offlineBanner(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.inkSecondary)
            Text("Can't reach Mochi right now.")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Check your Wi-Fi connection.")
                .font(Theme.section)
                .foregroundStyle(Theme.inkSecondary)
            Button("Retry") {
                Task { await petVM.retry() }
            }
            .buttonStyle(MellowFilledButtonStyle())
            Button("Use demo data instead") {
                AppSettings.shared.useMockData = true
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.link)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding()
    }

    // MARK: - Mock Badge
    @ViewBuilder
    private var mockBadge: some View {
        if AppSettings.shared.useMockData {
            MellowPill(text: "DEMO", fill: Theme.yellow)
        } else {
            MellowPill(text: "LIVE", fill: Theme.teal)
        }
    }
}

#Preview {
    PetView(petVM: .previewLoaded(), healthVM: HealthViewModel())
}
