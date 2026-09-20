import SwiftUI

/// One goal: progress ring, pace, and its contribution log.
struct GoalDetailView: View {
    let goalId: String
    var goalsVM: GoalsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showContribution = false
    @State private var editorMode: GoalEditorView.Mode?
    @State private var confirmDelete = false
    /// AI-written suggestion for this goal. Absent until (and unless) the AI answers.
    @State private var advice: String?

    private var goal: Goal? { goalsVM.goal(id: goalId) }
    private var log: [Contribution] { goalsVM.contributions[goalId] ?? [] }
    private var canDelete: Bool { log.allSatisfy { $0.source == .seed } }

    var body: some View {
        Group {
            if let goal {
                content(goal)
            } else if goalsVM.loadState.isSuccess {
                // Loaded, and the goal really is gone.
                Color.clear.onAppear { dismiss() }
            } else {
                ProgressView()
            }
        }
        .background(Theme.background)
        .navigationTitle(goal?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if let goal {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit", systemImage: "pencil") { editorMode = .edit(goal) }
                        if goalsVM.primaryGoal?.id != goal.id, goal.status == .active {
                            Button("Make primary", systemImage: "star") { Task { await goalsVM.setPrimary(goalId: goal.id) } }
                        }
                        Button("Archive", systemImage: "archivebox") {
                            Task {
                                await goalsVM.archive(goalId: goal.id)
                                dismiss()
                            }
                        }
                        if canDelete {
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Goal options")
                }
            }
        }
        .sheet(isPresented: $showContribution) {
            if let goal {
                ContributionSheet(goal: goal) { amount, note in
                    await goalsVM.contribute(goalId: goal.id, amount: amount, source: .manual, note: note)
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            GoalEditorView(mode: mode) { draft in
                await goalsVM.update(goalId: goalId, draft: draft) != nil
            }
        }
        .confirmationDialog("Delete this goal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete goal", role: .destructive) {
                Task {
                    await goalsVM.delete(goalId: goalId)
                    dismiss()
                }
            }
        }
        .goalsErrorAlert(goalsVM)
        .task {
            if goalsVM.snapshot.goals.isEmpty { await goalsVM.load() }
            await goalsVM.loadContributions(goalId: goalId)
        }
        // Re-ask whenever the balance changes, since the advice depends on the numbers.
        .task(id: goal?.current) {
            guard let goal, goal.status == .active else { return }
            advice = await AIWriter.shared.text(kind: .goal, facts: goal.aiFacts)
        }
    }

    // MARK: - Content
    private func content(_ goal: Goal) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                progressRing(goal)
                statRow(goal)
                paceCard(goal)
                logSection(goal)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func progressRing(_ goal: Goal) -> some View {
        ZStack {
            Circle().stroke(Theme.sage, lineWidth: 16)
            Circle()
                .trim(from: 0, to: goal.progress)
                .stroke(Theme.indigo, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.75), value: goal.progress)

            VStack(spacing: 2) {
                Image(systemName: goal.symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.indigo)
                Text("\(goal.progressPercent)%")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                Text(goal.milestone.title)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(width: 210, height: 210)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(goal.name) progress")
        .accessibilityValue("\(goal.progressPercent) percent, \(Money.string(goal.current)) of \(Money.string(goal.target))")
    }

    private func statRow(_ goal: Goal) -> some View {
        HStack(spacing: 12) {
            statCard("Saved", Money.string(goal.current), fill: Theme.teal)
            statCard("To go", Money.string(goal.remaining), fill: Theme.yellow)
            statCard("Target", Money.string(goal.target), fill: Theme.periwinkle)
        }
    }

    private func statCard(_ title: String, _ value: String, fill: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.system(.caption2, design: .rounded))
                .opacity(0.75)
        }
        .foregroundStyle(Theme.onPastel)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .mellowCard(fill, radius: 20)
        .accessibilityElement(children: .combine)
    }

    private func paceCard(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MochiView(mood: goal.milestone >= .almost ? .excited : .happy, milestone: goal.milestone, size: 52, animated: false)
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(0.55), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.milestone.title).font(Theme.label)
                    Text(goal.paceText ?? goal.milestone.subtitle)
                        .font(Theme.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }

            if let advice, goal.status == .active {
                Label(advice, systemImage: "sparkles")
                    .font(.system(.subheadline, design: .rounded))
                    .labelStyle(TopAlignedLabelStyle())
                    .accessibilityLabel("AI-written suggestion. \(advice)")
                Text("AI-written")
                    .font(.system(.caption2, design: .rounded))
                    .opacity(0.6)
                    .padding(.top, -8)
            }

            if goal.status == .active {
                Button {
                    showContribution = true
                } label: {
                    Label("Add money", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MellowFilledButtonStyle(fill: Theme.navy))
            }
        }
        .foregroundStyle(Theme.onPastel)
        .padding(18)
        .mellowCard(Theme.lime)
    }

    // MARK: - Log
    private func logSection(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MellowSectionHeader(title: "Contributions")

            if log.isEmpty {
                Text("Nothing here yet. Your first save will show up here.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .mellowCard(Theme.lime, radius: 20)
            } else {
                ForEach(groupedLog, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                logRow(item)
                                if index < group.items.count - 1 {
                                    Divider().overlay(Theme.separator).padding(.leading, 64)
                                }
                            }
                        }
                        .mellowCard(radius: 22, elevated: true)
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var groupedLog: [(day: Date, items: [Contribution])] {
        let cal = Calendar.current
        return Dictionary(grouping: log) { cal.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private func logRow(_ item: Contribution) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: item.source.systemImage, fill: item.isWithdrawal ? Theme.coral.opacity(0.5) : Theme.sage, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.note ?? item.source.title)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(item.source.title)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            Text(Money.signed(item.amount))
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(item.isWithdrawal ? Theme.ink : Theme.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Error alert
extension View {
    /// Shows `GoalsViewModel.errorMessage` in an alert.
    func goalsErrorAlert(_ goalsVM: GoalsViewModel) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { goalsVM.errorMessage != nil },
                set: { if !$0 { goalsVM.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(goalsVM.errorMessage ?? "")
        }
    }
}

/// Icon at the top-left with wrapped text beside it.
struct TopAlignedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}
