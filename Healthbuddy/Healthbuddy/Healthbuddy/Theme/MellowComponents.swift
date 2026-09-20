import SwiftUI

// MARK: - Card surface
extension View {
    /// Rounded card in the Mellow style. Use `elevated` for white cards sitting on the white ground.
    func mellowCard(
        _ fill: Color = Theme.surface,
        radius: CGFloat = Theme.cardRadius,
        elevated: Bool = false
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(elevated ? 0.07 : 0), radius: 14, x: 0, y: 5)
    }
}

// MARK: - Screen header
/// Large greeting + supporting line, as on the template's Home screen.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.greeting)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.lead)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Section header
struct MellowSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.section)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.link)
            }
        }
    }
}

// MARK: - Progress bar
struct MellowProgressBar: View {
    /// 0...1
    let value: Double
    var fill: Color = Theme.indigo
    var track: Color = Theme.indigo.opacity(0.15)
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(geo.size.width * min(max(value, 0), 1), height))
                    .animation(.spring(response: 0.6, dampingFraction: 0.75), value: value)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
    }
}

// MARK: - Pill
struct MellowPill: View {
    let text: String
    var fill: Color = Theme.sage
    var foreground: Color = Theme.onPastel

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
            .foregroundStyle(foreground)
    }
}

// MARK: - Icon tile
/// Rounded square holding an SF Symbol, used for list rows and tips.
struct IconTile: View {
    let systemImage: String
    var fill: Color = Theme.sage
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.onPastel)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons
struct MellowFilledButtonStyle: ButtonStyle {
    var fill: Color = Theme.indigo
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(fill, in: Capsule())
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Stat bubble
/// Sage circle with an optional progress ring, as in the template's mood row.
struct StatBubble<Glyph: View>: View {
    let value: String
    let label: String
    /// 0...1 ring around the circle. Omit for a plain bubble.
    var ring: Double?
    @ViewBuilder var glyph: () -> Glyph

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.sage)
                if let ring {
                    Circle()
                        .trim(from: 0, to: min(max(ring, 0), 1))
                        .stroke(Theme.indigo, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .animation(.spring(response: 0.7, dampingFraction: 0.75), value: ring)
                }
                glyph()
                    .foregroundStyle(Theme.onPastel)
            }
            .frame(width: 58, height: 58)

            VStack(spacing: 1) {
                Text(value)
                    .font(.system(.footnote, design: .rounded, weight: .bold).monospacedDigit())
                Text(label)
                    .font(.system(.caption2, design: .rounded))
                    .opacity(0.7)
            }
            .foregroundStyle(Theme.onPastel)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Pastel tile
/// Colored tile with a label anchored bottom-left, mirroring the template's "work on today" cards.
struct PastelTile: View {
    let title: String
    let value: String
    var caption: String?
    let systemImage: String
    let fill: Color
    /// 0...1. Adds a progress bar.
    var progress: Double?
    var minHeight: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.55), in: Circle())
                .accessibilityHidden(true)

            Spacer(minLength: 14)

            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .opacity(0.75)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.system(.caption2, design: .rounded))
                    .opacity(0.75)
            }
            if let progress {
                MellowProgressBar(value: progress, fill: Theme.navy, track: .white.opacity(0.5), height: 6)
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(Theme.onPastel)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
