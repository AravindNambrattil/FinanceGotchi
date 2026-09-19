import SwiftUI

/// "Add money" sheet for a goal.
struct ContributionSheet: View {
    let goal: Goal
    var onSubmit: (_ amount: Double, _ note: String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var note = ""
    @State private var isSaving = false
    @FocusState private var amountFocused: Bool

    private static let quickAmounts: [Double] = [5, 10, 25, 50]

    private var amount: Double? {
        guard let value = Double(amountText.replacingOccurrences(of: ",", with: "")), value > 0 else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                IconTile(systemImage: goal.symbol, fill: Theme.teal, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add to \(goal.name)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("\(Money.string(goal.remaining)) to go")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .foregroundStyle(Theme.ink)
            }

            HStack(spacing: 10) {
                ForEach(Self.quickAmounts, id: \.self) { value in
                    Button(Money.string(value)) { amountText = value.formatted(.number.grouping(.never)) }
                        .buttonStyle(MellowFilledButtonStyle(fill: Theme.sage, foreground: Theme.onPastel))
                }
            }

            TextField("Add a note (optional)", text: $note)
                .padding(14)
                .background(Theme.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(Theme.onPastel)

            Button {
                guard let amount else { return }
                Task {
                    isSaving = true
                    await onSubmit(amount, note)
                    isSaving = false
                    dismiss()
                }
            } label: {
                Text(amount.map { "Add \(Money.string($0))" } ?? "Enter an amount")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MellowFilledButtonStyle(fill: amount == nil ? Theme.lavender : Theme.indigo, foreground: amount == nil ? Theme.onPastel : .white))
            .disabled(amount == nil || isSaving)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .presentationDetents([.medium])
        .onAppear { amountFocused = true }
    }
}
