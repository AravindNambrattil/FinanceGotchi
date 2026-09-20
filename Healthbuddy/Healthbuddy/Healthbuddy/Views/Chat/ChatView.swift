import SwiftUI

/// Chat with Mochi. Answers are written by the AI from the app's own numbers and labelled as such.
struct ChatView: View {
    var chatVM: ChatViewModel
    var petVM: PetViewModel
    var goalsVM: GoalsViewModel
    var financialVM: FinancialViewModel
    var healthVM: HealthViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    private var mood: PetState.MoodExpression { petVM.petState?.moodExpression ?? .happy }
    private var petName: String { petVM.petState?.name ?? "Mochi" }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        bubble(ChatMessage(role: .mochi, text: "Hi! I'm \(petName). Ask me about your goals, saving, staying active, sleep or just how your week is going."))
                        ForEach(chatVM.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if chatVM.isReplying {
                            typingIndicator.id("typing")
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chatVM.messages.count) { scrollToEnd(proxy) }
                .onChange(of: chatVM.isReplying) { scrollToEnd(proxy) }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { inputArea }
            .navigationTitle("Chat with \(petName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", systemImage: "trash") { chatVM.clear() }
                        .disabled(chatVM.messages.isEmpty)
                }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if chatVM.isReplying {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = chatVM.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Bubbles
    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) } else { avatar }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(isUser ? Color.white : Theme.onPastel)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser ? Theme.indigo : Theme.sky.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                if message.isAI {
                    Text("AI-written")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 6)
                }
            }
            if !isUser { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : petName): \(message.text)\(message.isAI ? ", written by AI" : "")")
    }

    private var avatar: some View {
        MochiView(name: petName, mood: mood, size: 26, animated: false)
            .frame(width: 34, height: 34)
            .background(Theme.periwinkle.opacity(0.35), in: Circle())
            .accessibilityHidden(true)
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            avatar
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("\(petName) is thinking...")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.sky.opacity(0.3), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .accessibilityLabel("\(petName) is thinking")
    }

    // MARK: - Input
    private var inputArea: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChatViewModel.suggestions, id: \.self) { suggestion in
                        Button {
                            ask(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.onPastel)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.lime, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(chatVM.isReplying)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }

            HStack(spacing: 10) {
                TextField("Ask \(petName) something", text: Bindable(chatVM).draft)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { ask(nil) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))

                Button {
                    ask(nil)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(chatVM.canSend ? Theme.indigo : Theme.lavender, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!chatVM.canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Theme.screenPadding)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.background)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private func ask(_ text: String?) {
        guard let pet = petVM.petState else { return }
        // Health numbers only go along when Apple Health is connected and has something to report.
        let hasHealth = healthVM.isAuthorized && (healthVM.steps > 0 || healthVM.exerciseMinutes > 0 || healthVM.activeEnergyKcal > 0)
        let facts = pet.aiChatFacts(
            goal: goalsVM.primaryGoal,
            transactions: financialVM.transactions,
            health: hasHealth ? HealthPayload(steps: healthVM.steps, activeEnergyKcal: healthVM.activeEnergyKcal, exerciseMinutes: healthVM.exerciseMinutes) : nil
        )
        Task { await chatVM.send(text, facts: facts) }
    }
}

#Preview {
    ChatView(chatVM: ChatViewModel(), petVM: .previewLoaded(), goalsVM: GoalsViewModel(), financialVM: FinancialViewModel(), healthVM: HealthViewModel())
}
