import SwiftUI

struct HealthActivityCard: View {
    var viewModel: HealthViewModel
    let petId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.pink.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "figure.run")
                            .font(.subheadline)
                            .foregroundStyle(.pink)
                    }
                    Text("Activity Today")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Metrics
    private var metricsRow: some View {
        HStack(spacing: 0) {
            metricCell(value: "\(viewModel.steps)", unit: "steps", icon: "shoeprints.fill", color: .green)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 44)
            metricCell(value: "\(Int(viewModel.activeEnergyKcal))", unit: "kcal", icon: "flame.fill", color: .orange)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 44)
            metricCell(value: "\(viewModel.exerciseMinutes)", unit: "min", icon: "bolt.heart.fill", color: .pink)
        }
        .padding(.vertical, 4)
    }

    private func metricCell(value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.pink.opacity(0.12))
            .foregroundStyle(.pink)
            .clipShape(Capsule())
        }
        .disabled(viewModel.isSyncing)
    }

    // MARK: - Connect Button
    private var connectButton: some View {
        Button {
            Task { await viewModel.requestAuthorization() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                Text("Connect Apple Health")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.pink.opacity(0.12))
            .foregroundStyle(.pink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
