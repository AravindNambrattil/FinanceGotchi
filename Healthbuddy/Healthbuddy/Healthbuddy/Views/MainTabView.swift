import SwiftUI

struct MainTabView: View {
    @State private var petVM = PetViewModel()
    @State private var financialVM = FinancialViewModel()
    @State private var healthVM = HealthViewModel()

    var body: some View {
        TabView {
            PetView(petVM: petVM, healthVM: healthVM)
                .tabItem {
                    Label("Pet", systemImage: "pawprint.fill")
                }

            moneyTab
                .tabItem {
                    Label("Money", systemImage: "dollarsign.circle.fill")
                }

            GoalsView(petVM: petVM)
                .tabItem {
                    Label("Goals", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
    }

    // MARK: - Money Tab
    @ViewBuilder
    private var moneyTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Financial Decision")
                    DecisionView(viewModel: financialVM, petVM: petVM)
                        .padding(.horizontal, 20)

                    sectionHeader("Recent Transactions")
                        .padding(.top, 8)
                    ActivityView(viewModel: financialVM)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Money")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
}

#Preview {
    MainTabView()
}
