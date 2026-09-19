import SwiftUI

struct ActivityView: View {
    var viewModel: FinancialViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let error = viewModel.errorMessage {
                errorView(message: error)
            } else if viewModel.transactions.isEmpty {
                emptyView
            } else {
                transactionList
            }
        }
        .task { await viewModel.loadTransactions() }
    }

    // MARK: - List
    private var transactionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.transactions.enumerated()), id: \.element.id) { index, tx in
                transactionRow(tx)
                if index < viewModel.transactions.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                        .padding(.trailing, 16)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tx.isPositive ? Color.green.opacity(0.12) : Color.red.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: categoryIcon(tx.category))
                    .font(.subheadline)
                    .foregroundStyle(tx.isPositive ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(tx.category.capitalized)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(String(format: "%@$%.2f", tx.isPositive ? "+" : "-", abs(tx.amount)))
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(tx.isPositive ? .green : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Error
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Can't load transactions")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadTransactions() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Empty
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No transactions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Helpers
    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "savings":  return "banknote.fill"
        case "income":   return "arrow.down.circle.fill"
        case "food":     return "fork.knife"
        case "tech":     return "headphones"
        default:         return "creditcard.fill"
        }
    }
}

#Preview {
    let vm = FinancialViewModel(service: MockPetService())
    vm.transactions = Transaction.mockTransactions
    return ScrollView {
        ActivityView(viewModel: vm).padding()
    }
}
