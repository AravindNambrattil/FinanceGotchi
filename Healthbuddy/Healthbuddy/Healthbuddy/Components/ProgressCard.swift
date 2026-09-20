import SwiftUI

struct ProgressCard: View {
    let label: String
    let value: Double       // 0.0 – 100.0
    let color: Color
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))%")
                    .font(.caption.bold())
                    .foregroundStyle(color)
            }
            ProgressView(value: value / 100)
                .tint(color)
                .animation(.easeInOut, value: value)
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        ProgressCard(label: "Needs", value: 85, color: .orange, icon: "heart.fill")
        ProgressCard(label: "Energy", value: 60, color: .blue, icon: "bolt.fill")
    }
    .padding()
}
