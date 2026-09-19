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
                        .overlay(Theme.separator)
                        .padding(.leading, 76)
                        .padding(.trailing, 16)
                }
            }
        }
        .mellowCard(elevated: true)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: 14) {
            IconTile(systemImage: categoryIcon(tx.category), fill: tx.isPositive ? Theme.sage : Theme.coral.opacity(0.45))

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                // The server often repeats the category as the title, so only show it when it adds something.
                if tx.category.caseInsensitiveCompare(tx.title) != .orderedSame {
                    Text(tx.category.capitalized)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
            Text(String(format: "%@$%.2f", tx.isPositive ? "+" : "-", abs(tx.amount)))
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(tx.isPositive ? Theme.link : Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Error
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(Theme.inkSecondary)
            Text("Can't load transactions")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadTransactions() }
            }
            .buttonStyle(MellowFilledButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Empty
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Theme.inkSecondary)
            Text("No transactions yet")
                .font(Theme.section)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Helpers
    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "savings":  return "banknote.fill"
        case "income":   return "arrow.down.circle.fill"
        case "food", "dining":          return "fork.knife"
        case "groceries", "essential":  return "cart.fill"
        case "entertainment":           return "ticket.fill"
        case "unexpected":              return "exclamationmark.triangle.fill"
        case "purchase", "want":        return "bag.fill"
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
