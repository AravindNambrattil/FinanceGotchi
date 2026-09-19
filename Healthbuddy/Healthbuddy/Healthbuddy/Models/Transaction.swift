import Foundation

struct Transaction: Codable, Identifiable {
    let id: String
    let title: String
    let amount: Double
    let category: String

    var isPositive: Bool { amount >= 0 }
}

// MARK: - Mock Data
extension Transaction {
    static let mockTransactions: [Transaction] = [
        Transaction(id: "1", title: "Coffee",                amount: -6.00,  category: "expense"),
        Transaction(id: "2", title: "Saved for Laptop Fund", amount: 20.00,  category: "savings"),
        Transaction(id: "3", title: "Groceries",             amount: -42.00, category: "essential"),
        Transaction(id: "4", title: "Emergency Fund",        amount: 15.00,  category: "savings"),
        Transaction(id: "5", title: "New Headphones",        amount: -25.00, category: "expense"),
        Transaction(id: "6", title: "Paycheck",              amount: 200.00, category: "income")
    ]
}
