import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case pet, money, goals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pet:   "Pet"
        case .money: "Money"
        case .goals: "Goals"
        }
    }

    var systemImage: String {
        switch self {
        case .pet:   "pawprint.fill"
        case .money: "dollarsign.circle.fill"
        case .goals: "chart.line.uptrend.xyaxis"
        }
    }
}

/// Indigo pill tab bar from the Mellow template: the selected tab expands into a white pill with its label.
/// The system tab bar is hidden in `MainTabView`; `TabView` still owns selection and keeps each tab's state alive.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        if isSelected {
                            Text(tab.title)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(isSelected ? Theme.onPastel : .white)
                    .padding(.horizontal, isSelected ? 20 : 16)
                    .frame(minHeight: 44)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.white)
                                .matchedGeometryEffect(id: "selection", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Theme.indigo, in: Capsule())
        .shadow(color: Theme.indigo.opacity(0.35), radius: 16, x: 0, y: 8)
        .padding(.bottom, 8)
    }
}

#Preview {
    @Previewable @State var tab = AppTab.pet
    return FloatingTabBar(selection: $tab)
        .padding()
}
