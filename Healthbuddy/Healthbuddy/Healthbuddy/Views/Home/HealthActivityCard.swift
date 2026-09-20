import SwiftUI

struct HealthActivityCard: View {
    var viewModel: HealthViewModel
    let petId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 12) {
                    IconTile(systemImage: "figure.run", fill: Theme.coral.opacity(0.45), size: 40)
                    Text("Activity Today")
                        .font(Theme.label)
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                if viewModel.isAuthorized {
                    syncButton
                }
            }

            if viewModel.isAuthorized {
                metricsRow
            } else {
                connectButton
            }

            if let message = viewModel.syncMessage {
                Text(message)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(20)
        .mellowCard(elevated: true)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }

    // MARK: - Metrics
    private var metricsRow: some View {
        HStack(spacing: 0) {
            metricCell(value: "\(viewModel.steps)", unit: "steps", icon: "shoeprints.fill")
            if viewModel.hasEnergyAndExercise {
                Rectangle().fill(Theme.separator).frame(width: 1, height: 44)
                metricCell(value: "\(Int(viewModel.activeEnergyKcal))", unit: "kcal", icon: "flame.fill")
                Rectangle().fill(Theme.separator).frame(width: 1, height: 44)
                metricCell(value: "\(viewModel.exerciseMinutes)", unit: "min", icon: "bolt.heart.fill")
            }
        }
        .padding(.vertical, 4)
    }

    private func metricCell(value: String, unit: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.indigo)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.ink)
            Text(unit)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sync Button
    private var syncButton: some View {
        Button {
            Task { await viewModel.syncActivity(petId: petId) }
        } label: {
            HStack(spacing: 5) {
                if viewModel.isSyncing {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                Text(viewModel.isSyncing ? "Syncing" : "Sync")
            }
        }
        .buttonStyle(MellowFilledButtonStyle(fill: Theme.sage, foreground: Theme.onPastel))
        .disabled(viewModel.isSyncing)
    }

    // MARK: - Connect Button
    private var connectButton: some View {
        Button {
            Task { await viewModel.requestAuthorization() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.hasEnergyAndExercise ? "heart.text.square.fill" : "figure.walk")
                Text(viewModel.hasEnergyAndExercise ? "Connect Apple Health" : "Count my steps")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MellowFilledButtonStyle())
    }
}
