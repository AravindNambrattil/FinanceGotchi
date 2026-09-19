import SwiftUI

struct MainTabView: View {
    @State private var petVM = PetViewModel()
    @State private var financialVM = FinancialViewModel()
    @State private var healthVM = HealthViewModel()
    @State private var goalsVM = GoalsViewModel()
    @State private var selection: AppTab = .pet
    private var settings = AppSettings.shared

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.pet.title, systemImage: AppTab.pet.systemImage, value: AppTab.pet) {
                PetView(petVM: petVM, healthVM: healthVM, onSeeAll: { selection = .goals })
                    .toolbarVisibility(.hidden, for: .tabBar)
            }

            Tab(AppTab.money.title, systemImage: AppTab.money.systemImage, value: AppTab.money) {
                moneyTab
                    .toolbarVisibility(.hidden, for: .tabBar)
            }

            Tab(AppTab.goals.title, systemImage: AppTab.goals.systemImage, value: AppTab.goals) {
                GoalsView(petVM: petVM, goalsVM: goalsVM)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(selection: $selection)
        }
        .background(Theme.background)
        .overlay {
            DecisionResultOverlay(viewModel: financialVM, petVM: petVM, goalsVM: goalsVM)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: financialVM.decisionResult != nil)
        .onChange(of: settings.useMockData) {
            // Demo <-> live changes every number on screen, so reload all of it.
            Task {
                await petVM.retry()
                await financialVM.loadTransactions()
                await financialVM.loadOffer()
                await goalsVM.refresh()
            }
        }
    }

    // MARK: - Money Tab
    private var moneyTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenHeader(title: "Money", subtitle: "Every choice helps Mochi grow.")

                    VStack(alignment: .leading, spacing: 12) {
                        MellowSectionHeader(title: "Financial decision")
                        DecisionView(viewModel: financialVM, petVM: petVM, goalsVM: goalsVM)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        MellowSectionHeader(title: "Recent transactions")
                        ActivityView(viewModel: financialVM)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    MainTabView()
}
