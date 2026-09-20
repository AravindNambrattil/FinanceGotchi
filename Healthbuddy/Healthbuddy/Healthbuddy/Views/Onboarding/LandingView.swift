import SwiftUI

/// First screen: what Mochi is, in the template's onboarding style (bright hero, teal panel).
struct LandingView: View {
    var onStart: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            hero
                .containerRelativeFrame(.vertical) { height, _ in height * 0.4 }

            panel
        }
        .background(Theme.background)
        .ignoresSafeArea(edges: .vertical)
    }

    // MARK: - Hero
    private var hero: some View {
        // Decorations live in an overlay of a flexible clear view: oversized shapes must not widen the layout.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { heroArt }
            .clipped()
    }

    private var heroArt: some View {
        ZStack {
            Ellipse()
                .fill(Theme.yellow)
                .frame(width: 560, height: 420)
                .offset(x: -80, y: -110)

            Capsule().fill(Theme.coral).frame(width: 74, height: 18).rotationEffect(.degrees(-6)).offset(x: -128, y: -52)
            Capsule().fill(Theme.pink).frame(width: 74, height: 18).rotationEffect(.degrees(-6)).offset(x: -110, y: -26)
            Image(systemName: "camera.macro")
                .font(.system(size: 64))
                .foregroundStyle(Theme.coral)
                .rotationEffect(.degrees(14))
                .offset(x: 128, y: -60)
                .accessibilityHidden(true)
            Circle().fill(Theme.periwinkle.opacity(0.55)).frame(width: 34, height: 34).offset(x: 138, y: 50)
            Image(systemName: "sparkle")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .offset(x: -132, y: 38)
                .accessibilityHidden(true)

            MochiView(mood: .happy, milestone: .halfway, size: 190)
                .offset(y: 14)
        }
    }

    // MARK: - Panel
    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Mochi")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white, in: Capsule())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your money,\nmade alive.")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("A tiny companion that turns saving, budgeting, and everyday money choices into something you can see, care for, and grow with.")
                        .font(.system(.callout, design: .rounded))
                        .opacity(0.85)
                }

                VStack(alignment: .leading, spacing: 12) {
                    bullet("hand.tap.fill", "Decide", "Buy, save, or wait. Mochi reacts to every choice.")
                    bullet("target", "Save", "Set goals and watch Mochi grow as you get closer.")
                    bullet("scalemass.fill", "Balance", "No guilt for spending. Mochi cheers for balance.")
                }

                VStack(spacing: 12) {
                    Button(action: onStart) {
                        Label("Get started", systemImage: "arrow.right")
                            .labelStyle(TrailingIconLabelStyle())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(MellowFilledButtonStyle(fill: Theme.navy))

                    Button("I already have an account", action: onSignIn)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .foregroundStyle(Theme.onPastel)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 48)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 64, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous)
                .fill(Theme.teal)
        )
    }

    private func bullet(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: symbol, fill: .white.opacity(0.7), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label)
                Text(text)
                    .font(Theme.caption)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Label with the icon after the title.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    LandingView(onStart: {}, onSignIn: {})
}
