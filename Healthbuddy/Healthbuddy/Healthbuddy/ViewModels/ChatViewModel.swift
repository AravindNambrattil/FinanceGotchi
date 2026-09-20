import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, mochi }

    let id = UUID()
    let role: Role
    let text: String
    /// Written by the model (shown with an "AI-written" label). Built-in lines and fallbacks are not.
    var isAI = false
}

/// A short conversation with Mochi. The model only ever answers from the facts the app sends with each question;
/// it never decides or calculates anything, and when it can't answer, the built-in fallback line is shown instead.
@Observable
@MainActor
final class ChatViewModel {
    static let suggestions = [
        "How is my goal going?",
        "How active have I been today?",
        "Give me a tip for today",
        "How can I save a bit more?",
        "How is my emergency fund?",
        "How do I sleep better?",
    ]

    static let fallback = "I couldn't come up with a good answer just now. Try again in a moment, or ask me another way."

    var messages: [ChatMessage] = []
    var draft = ""
    var isReplying = false

    @ObservationIgnored private let writer: AIWriter
    @ObservationIgnored private var token = UUID()

    init(writer: AIWriter = .shared) {
        self.writer = writer
    }

    var canSend: Bool { !isReplying && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Sends the draft (or `text`, for a suggestion chip). `facts` is rebuilt by the caller for every question so
    /// answers reflect what is on screen right now.
    func send(_ text: String? = nil, facts: [String: AIFact]) async {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isReplying else { return }

        // Only real exchanges go back to the model as history, not our own fallback lines.
        let history = messages.filter { $0.isAI || $0.role == .user }.suffix(6).map {
            AIChatTurn(role: $0.role == .user ? "user" : "assistant", text: $0.text)
        }

        messages.append(ChatMessage(role: .user, text: question))
        draft = ""
        isReplying = true
        let mine = UUID()
        token = mine

        let reply = await writer.chat(message: question, facts: facts, history: Array(history))
        guard token == mine else { return }   // conversation was cleared while waiting
        if let reply {
            messages.append(ChatMessage(role: .mochi, text: reply, isAI: true))
        } else {
            messages.append(ChatMessage(role: .mochi, text: Self.fallback))
        }
        isReplying = false
    }

    func clear() {
        token = UUID()
        messages = []
        draft = ""
        isReplying = false
    }
}
