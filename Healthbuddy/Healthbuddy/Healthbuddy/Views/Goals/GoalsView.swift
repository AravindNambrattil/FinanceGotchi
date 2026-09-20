import SwiftUI

struct GoalsView: View {
    var petVM: PetViewModel
    var goalsVM: GoalsViewModel

    @Environment(SessionStore.self) private var session
    @State private var settings = AppSettings.shared
    @State private var editorMode: GoalEditorView.Mode?
    @State private var contributionGoal: Goal?

    private var pet: PetState? { petVM.petState }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let pet {
                        savingsScoreCard(pet: pet)
                    }

                    if let goal = goalsVM.primaryGoal {
                        primaryGoalCard(goal)
                    } else if goalsVM.loadState.isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        emptyGoalsCard
                    }

                    otherGoalsSection

                    if let pet {
                        emergencyFundCard(pet: pet)
                        savingStreakCard(pet: pet)
                    }
                    tipsSection
                    accountCard
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { goalId in
                GoalDetailView(goalId: goalId, goalsVM: goalsVM)
            }
        }
        .sheet(item: $editorMode) { mode in
            GoalEditorView(mode: mode) { draft in
                await goalsVM.create(draft) != nil
            }
        }
        .sheet(item: $contributionGoal) { goal in
            ContributionSheet(goal: goal) { amount, note in
                await goalsVM.contribute(goalId: goal.id, amount: amount, source: .manual, note: note)
            }
        }
        .overlay { celebrationOverlay }
        .sensoryFeedback(trigger: goalsVM.celebration) { _, new in new != nil ? .success : nil }
        .goalsErrorAlert(goalsVM)
        .task {
            await goalsVM.load()
            if petVM.petState == nil { await petVM.loadPetState() }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .top) {
            ScreenHeader(title: "Goals", subtitle: "Small saves, big wins.")
            Button {
                editorMode = .create
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.indigo, in: Circle())
            }
            .accessibilityLabel("New goal")
        }
    }

    // MARK: - Primary goal
    private func primaryGoalCard(_ goal: Goal) -> some View {
        NavigationLink(value: goal.id) {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    MochiView(
                        mood: goal.milestone >= .almost ? .excited : (pet?.moodExpression ?? .happy),
                        milestone: goal.milestone,
                        size: 84
                    )
                    .frame(width: 96, height: 96)
                    .background(.white.opacity(0.45), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Current goal", systemImage: goal.symbol)
                            .font(Theme.caption)
                            .opacity(0.8)
                        Text(goal.name)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .lineLimit(1)
                        Text(Money.string(goal.current))
                            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.navy)
                        Text("of \(Money.string(goal.target))")
                            .font(Theme.caption)
                            .opacity(0.8)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 6) {
                    MellowProgressBar(value: goal.progress, fill: Theme.navy, track: .white.opacity(0.55), height: 14)
                    HStack {
                        Text("\(goal.progressPercent)% complete")
                            .font(Theme.caption)
                            .opacity(0.8)
                        Spacer()
                        Text("\(Money.string(goal.remaining)) to go")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                }

                milestoneBanner(goal)

                if goal.status == .active {
                    Button {
                        contributionGoal = goal
                    } label: {
                        Label("Add money", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MellowFilledButtonStyle(fill: Theme.navy))
                }
            }
            .foregroundStyle(Theme.onPastel)
            .padding(20)
            .mellowCard(Theme.teal)
        }
        .buttonStyle(.plain)
    }

    private func milestoneBanner(_ goal: Goal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.milestone == .reached ? "party.popper.fill" : "sparkles")
                .font(.title3)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.milestone.title).font(Theme.label)
                Text(goal.paceText ?? goal.milestone.subtitle)
                    .font(Theme.caption)
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var emptyGoalsCard: some View {
        VStack(spacing: 14) {
            MochiView(mood: .neutral, size: 96)
            Text("Pick something to save for")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.onPastel)
            Text("A laptop, a trip, a rainy-day buffer. Mochi will cheer you on.")
                .font(Theme.caption)
                .foregroundStyle(Theme.onPastel.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Create a goal") { editorMode = .create }
                .buttonStyle(MellowFilledButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .mellowCard(Theme.lime)
    }

    // MARK: - Other goals
    @ViewBuilder
    private var otherGoalsSection: some View {
        let others = goalsVM.trackedGoals.filter { $0.id != goalsVM.primaryGoal?.id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                MellowSectionHeader(title: "Your goals")
                    .padding(.top, 8)
                ForEach(others) { goal in
                    NavigationLink(value: goal.id) {
                        GoalRow(goal: goal)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if goal.status == .active {
                            Button("Add money", systemImage: "plus") { contributionGoal = goal }
                            Button("Make primary", systemImage: "star") { Task { await goalsVM.setPrimary(goalId: goal.id) } }
                        }
                        Button("Archive", systemImage: "archivebox") { Task { await goalsVM.archive(goalId: goal.id) } }
                    }
                }
            }
        }
    }

    // MARK: - Celebration
    @ViewBuilder
    private var celebrationOverlay: some View {
        if let band = goalsVM.celebration {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { goalsVM.dismissCelebration() }

                VStack(spacing: 16) {
                    MochiView(mood: .excited, milestone: band, size: 120)
                    Text(band.title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(band.subtitle)
                        .font(Theme.lead)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                    Button("Yay!") { goalsVM.dismissCelebration() }
                        .buttonStyle(MellowFilledButtonStyle())
                }
                .padding(32)
                .mellowCard(Theme.surface, radius: 32)
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
                .padding(.horizontal, 28)
                .transition(.scale(scale: 0.9).combined(with: .opacity))

                ConfettiView().ignoresSafeArea()
            }
            .transition(.opacity)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: goalsVM.celebration)
        }
    }

    // MARK: - Savings Score Card
    private func savingsScoreCard(pet: PetState) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.sage, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: pet.savingsScore / 100)
                    .stroke(Theme.indigo, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: pet.savingsScore)
                Text("\(Int(pet.savingsScore))")
                    .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
            }
            .frame(width: 84, height: 84)
            .padding(4.5)

            VStack(alignment: .leading, spacing: 8) {
                Text("Savings Health")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                HStack(spacing: 8) {
                    MellowPill(text: scoreLabel(pet.savingsScore), fill: scoreColor(pet.savingsScore))
                    if pet.savingStreak > 0 {
                        Label("\(pet.savingStreak) day streak", systemImage: "flame.fill")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.onPastel)
        .padding(20)
        .mellowCard(Theme.lime)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Emergency Fund
    private func emergencyFundCard(pet: PetState) -> some View {
        let saved = goalsVM.emergencyGoal?.current ?? pet.emergencyFund
        let target = goalsVM.emergencyGoal?.target ?? pet.emergencyFundTarget
        let progress = min(saved / max(target, 1), 1.0)
        let isHealthy = progress >= 0.5

        return VStack(spacing: 16) {
            HStack {
                HStack(spacing: 12) {
                    IconTile(systemImage: "shield.fill", fill: .white.opacity(0.6), size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency Fund")
                            .font(Theme.label)
                        Text(isHealthy ? "Looking healthy" : "Still building")
                            .font(Theme.caption)
                            .opacity(0.75)
                    }
                }
                Spacer()
                MellowPill(text: isHealthy ? "Healthy" : "Building", fill: isHealthy ? Theme.sage : Theme.yellow)
            }

            VStack(spacing: 6) {
                MellowProgressBar(value: progress, fill: Theme.navy, track: .white.opacity(0.55), height: 10)
                HStack {
                    Text("\(Money.string(saved)) saved")
                        .font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit())
                    Spacer()
                    Text("Goal: \(Money.string(target))")
                        .font(Theme.caption)
                        .opacity(0.75)
                }
            }
        }
        .foregroundStyle(Theme.onPastel)
        .padding(20)
        .mellowCard(Theme.periwinkle)
    }

    // MARK: - Saving Streak Card
    private func savingStreakCard(pet: PetState) -> some View {
        HStack(spacing: 16) {
            Image(systemName: pet.savingStreak > 0 ? "flame.fill" : "moon.zzz.fill")
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.6), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Saving Streak")
                    .font(Theme.label)
                Text(pet.savingStreak > 0
                     ? "\(pet.savingStreak) day\(pet.savingStreak == 1 ? "" : "s") and counting!"
                     : "Save today to start a streak")
                    .font(Theme.caption)
                    .opacity(0.8)
            }

            Spacer()

            if pet.savingStreak > 0 {
                Text("\(pet.savingStreak)")
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.navy)
            }
        }
        .foregroundStyle(Theme.onPastel)
        .padding(20)
        .mellowCard(Theme.yellow)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tips Section
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MellowSectionHeader(title: "Tips from Mochi")
                .padding(.top, 8)

            VStack(spacing: 12) {
                tipCard(icon: "banknote.fill",         color: Theme.sage,       title: "Consistent Saving",     body: "Even small daily saves add up. Each one boosts your score and keeps Mochi happy.")
                tipCard(icon: "shield.fill",            color: Theme.periwinkle, title: "Emergency Fund First",  body: "A buffer means unexpected expenses won't derail your goals, or stress out Mochi.")
                tipCard(icon: "scalemass.fill",         color: Theme.pink,       title: "Balance Needs & Wants", body: "Mochi doesn't judge spending. The goal is balance, not denial.")
                tipCard(icon: "clock.arrow.circlepath", color: Theme.yellow,     title: "Patience Pays Off",     body: "Long-term goals feel slow, but every step forward is progress Mochi can feel.")
            }
        }
    }

    private func tipCard(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(systemImage: icon, fill: color, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                Text(body)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mellowCard(elevated: true)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Account
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            MellowSectionHeader(title: "Account")
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "person.fill", fill: Theme.periwinkle.opacity(0.6), size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayName.isEmpty ? "Signed in" : "Hi, \(session.displayName)")
                            .font(Theme.label)
                            .foregroundStyle(Theme.ink)
                        Text(session.email.isEmpty ? "Demo account" : session.email)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Toggle(isOn: Binding(get: { !settings.useMockData }, set: { settings.useMockData = !$0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live server").font(Theme.label).foregroundStyle(Theme.ink)
                        Text(settings.useMockData ? "Off: showing demo data stored on this device." : "On: real data from Mochi's server and bank.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .tint(Theme.indigo)

                HStack(spacing: 10) {
                    Button("Replay intro", action: session.replayIntro)
                        .buttonStyle(MellowFilledButtonStyle(fill: Theme.sage, foreground: Theme.onPastel))
                    Button("Sign out", action: session.signOut)
                        .buttonStyle(MellowFilledButtonStyle(fill: Theme.coral, foreground: Theme.onPastel))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mellowCard(elevated: true)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        }
    }

    // MARK: - Helpers
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return Theme.teal
        case 50...: return Theme.yellow
        default:    return Theme.coral
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

extension LoadState {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

#Preview {
    GoalsView(petVM: .previewLoaded(), goalsVM: .previewLoaded())
        .environment(SessionStore())
}
