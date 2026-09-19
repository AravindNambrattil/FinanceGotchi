import SwiftUI

/// Create / edit form, presented as a sheet.
struct GoalEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(Goal)

        var id: String {
            switch self {
            case .create:        "create"
            case .edit(let goal): "edit-\(goal.id)"
            }
        }
    }

    let mode: Mode
    /// Returns true when the save succeeded and the sheet can close.
    var onSave: (GoalDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "star.fill"
    @State private var targetText = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @State private var isSaving = false
    @FocusState private var focus: Field?

    private enum Field { case name, target }

    private static let symbols = [
        "star.fill", "laptopcomputer", "airplane.departure", "house.fill",
        "car.fill", "graduationcap.fill", "gift.fill", "bicycle",
        "iphone", "camera.fill", "gamecontroller.fill", "heart.fill",
    ]

    private var target: Double? {
        Double(targetText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    private var draft: GoalDraft {
        GoalDraft(name: name, symbol: symbol, target: target ?? 0, deadline: hasDeadline ? deadline : nil)
    }

    private var title: String {
        if case .edit = mode { return "Edit goal" }
        return "New goal"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you saving for?") {
                    TextField("e.g. New laptop", text: $name)
                        .focused($focus, equals: .name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .onSubmit { focus = .target }
                }

                Section("How much do you need?") {
                    HStack {
                        Text("$").foregroundStyle(Theme.inkSecondary)
                        TextField("1,000", text: $targetText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .target)
                    }
                }

                Section("Pick an icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(Self.symbols, id: \.self) { option in
                            Button {
                                symbol = option
                            } label: {
                                Image(systemName: option)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.onPastel)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(
                                        symbol == option ? Theme.teal : Theme.sage.opacity(0.45),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                    .overlay {
                                        if symbol == option {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(Theme.indigo, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(symbol == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Set a target date", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Finish by", selection: $deadline, in: Date.now..., displayedComponents: .date)
                    }
                } footer: {
                    Text("Optional. Mochi will suggest a weekly amount to get there.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        Task {
                            isSaving = true
                            if await onSave(draft) { dismiss() }
                            isSaving = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isValid || isSaving)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private func load() {
        guard case .edit(let goal) = mode else {
            focus = .name
            return
        }
        name = goal.name
        symbol = goal.symbol
        targetText = goal.target.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
        if let existing = goal.deadline {
            hasDeadline = true
            deadline = existing
        }
    }
}
