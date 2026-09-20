import SwiftUI

/// A sentence written by the AI, always labelled as such. Only shown when the AI actually produced something.
struct AITextCard: View {
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.65), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .opacity(0.75)
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("AI-written")
                    .font(.system(.caption2, design: .rounded))
                    .opacity(0.6)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.onPastel)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mellowCard(Theme.sky.opacity(0.55), radius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), written by AI. \(text)")
    }
}
