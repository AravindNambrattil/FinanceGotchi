import SwiftUI

/// Landing page, then three swipeable pages, then hands off to sign-in.
struct WelcomeFlow: View {
    var session: SessionStore
    @State private var showPages = false

    var body: some View {
        ZStack {
            if showPages {
                OnboardingView(onFinish: { session.hasOnboarded = true })
                    .transition(.move(edge: .trailing))
            } else {
                LandingView(
                    onStart: { showPages = true },
                    onSignIn: { session.hasOnboarded = true }
                )
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showPages)
    }
}

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let fill: Color
        let title: String
        let text: String
        let mood: PetState.MoodExpression
        let milestone: GoalMilestone
    }

    private static let pages = [
        Page(id: 0, fill: Theme.yellow, title: "Meet Mochi", text: "Mochi lives on your phone and on your desk. How Mochi feels reflects the choices you make with your money.", mood: .happy, milestone: .starting),
        Page(id: 1, fill: Theme.periwinkle, title: "Your choices shape Mochi", text: "Buy, save, or wait. Every decision changes Mochi's mood and needs, and there's no wrong answer, just balance.", mood: .excited, milestone: .growing),
        Page(id: 2, fill: Theme.teal, title: "Goals make saving real", text: "Pick something to save for. As your goal fills up, Mochi grows: a leaf, a scarf, sparkles, and finally a party hat.", mood: .excited, milestone: .reached),
    ]

    private var isLast: Bool { page == Self.pages.count - 1 }

    var body: some View {
        TabView(selection: $page) {
            ForEach(Self.pages) { item in
                pageView(item).tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.background)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { controls }
        .overlay(alignment: .topTrailing) {
            if !isLast {
                Button("Skip", action: onFinish)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.onPastel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.8), in: Capsule())
                    .padding(.trailing, 20)
                    .padding(.top, 8)
            }
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 0) {
            item.fill
                .frame(maxWidth: .infinity)
                .overlay {
                    ZStack {
                        Circle().fill(.white.opacity(0.25)).frame(width: 300, height: 300).offset(x: 90, y: -60)
                        Circle().fill(.white.opacity(0.18)).frame(width: 170, height: 170).offset(x: -110, y: 70)
                        Image(systemName: "sparkle")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .offset(x: -120, y: -90)
                            .accessibilityHidden(true)
                        MochiView(mood: item.mood, milestone: item.milestone, size: 220)
                            .offset(y: 16)
                    }
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 48, bottomTrailingRadius: 0, style: .continuous))
                .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 12) {
                Text(item.title)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(item.text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
    }

    // MARK: - Controls
    private var controls: some View {
        HStack(spacing: 20) {
            // Progress bar, as in the template's onboarding.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.lavender.opacity(0.6))
                    Capsule()
                        .fill(Theme.navy)
                        .frame(width: geo.size.width * CGFloat(page + 1) / CGFloat(Self.pages.count))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
                }
            }
            .frame(height: 10)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(Self.pages.count)")

            Button(action: advance) {
                Image(systemName: isLast ? "checkmark" : "arrow.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Theme.navy, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(isLast ? "Finish" : "Next page")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
    }

    private func advance() {
        if isLast {
            onFinish()
        } else {
            withAnimation { page += 1 }
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
