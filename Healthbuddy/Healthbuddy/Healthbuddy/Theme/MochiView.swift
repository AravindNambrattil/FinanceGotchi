import SwiftUI

/// Mochi, drawn from SwiftUI shapes: no bundled art, no licensing, and nothing that can render as a `?` box.
///
/// - `mood` changes the face (and body tint). `milestone` adds decorations cumulatively, matching the goal
///   bands in CLAUDE.md: a leaf at 25%, a scarf at 50%, sparkles at 75%, a party hat at 100%.
/// - Idle animation (breathing, blinking, twinkling) stops under Reduce Motion or when `animated` is false.
struct MochiView: View {
    var name: String = "Mochi"
    var mood: PetState.MoodExpression = .happy
    var milestone: GoalMilestone = .starting
    var size: CGFloat = 120
    var animated: Bool = true
    /// Overrides the mood tint, e.g. to tell Byte apart from Mochi.
    var tint: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var blinking = false
    @State private var twinkling = false

    private var canAnimate: Bool { animated && !reduceMotion }
    private var s: CGFloat { size }

    private var bodyColor: Color {
        if let tint { return tint }
        switch mood {
        case .happy, .neutral: return Theme.sage
        case .excited:         return Theme.yellow
        case .sad:             return Theme.lavender
        }
    }

    var body: some View {
        ZStack {
            ears
            bodyShape
            face
            if milestone >= .halfway { scarf }
            if milestone >= .growing { leaf }
            if milestone >= .reached { partyHat }
            if milestone >= .almost { sparkles }
        }
        .frame(width: s, height: s)
        .scaleEffect(x: breathing ? 1.02 : 1, y: breathing ? 0.985 : 1, anchor: .bottom)
        .offset(y: mood == .excited && breathing ? -s * 0.05 : 0)
        .task(id: mood) { await startBreathing() }
        .task(id: canAnimate) { await blinkLoop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), feeling \(mood.label.lowercased())")
    }

    // MARK: - Body
    private var bodyShape: some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.42, style: .continuous)
                .fill(bodyColor)
            // Soft belly highlight.
            Ellipse()
                .fill(.white.opacity(0.35))
                .frame(width: s * 0.5, height: s * 0.26)
                .offset(y: s * 0.2)
        }
        .frame(width: s * 0.86, height: s * 0.78)
        .offset(y: s * 0.09)
    }

    private var ears: some View {
        HStack(spacing: s * 0.34) {
            ear
            ear
        }
        .offset(y: -s * 0.29)
    }

    private var ear: some View {
        ZStack {
            Circle().fill(bodyColor)
            Circle().fill(Theme.pink.opacity(0.55)).padding(s * 0.05)
        }
        .frame(width: s * 0.24, height: s * 0.24)
    }

    // MARK: - Face
    private var face: some View {
        ZStack {
            eyes
            cheeks
            mouth
            if mood == .sad { tear }
        }
        .offset(y: s * 0.07)
    }

    @ViewBuilder
    private var eyes: some View {
        HStack(spacing: s * 0.24) {
            eye
            eye
        }
        .offset(y: -s * 0.04)
    }

    @ViewBuilder
    private var eye: some View {
        if mood == .excited {
            // Happy "^" eyes.
            CurveShape(bend: -1)
                .stroke(Theme.onPastel, style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
                .frame(width: s * 0.13, height: s * 0.09)
        } else {
            Capsule()
                .fill(Theme.onPastel)
                .frame(width: s * 0.1, height: blinking ? s * 0.02 : s * 0.15)
                .frame(height: s * 0.15)
        }
    }

    private var cheeks: some View {
        HStack(spacing: s * 0.4) {
            Ellipse().fill(Theme.coral.opacity(0.4)).frame(width: s * 0.12, height: s * 0.075)
            Ellipse().fill(Theme.coral.opacity(0.4)).frame(width: s * 0.12, height: s * 0.075)
        }
        .offset(y: s * 0.07)
    }

    @ViewBuilder
    private var mouth: some View {
        Group {
            switch mood {
            case .happy:
                CurveShape(bend: 1)
                    .stroke(Theme.onPastel, style: StrokeStyle(lineWidth: s * 0.034, lineCap: .round))
                    .frame(width: s * 0.15, height: s * 0.08)
            case .excited:
                OpenMouthShape()
                    .fill(Theme.onPastel)
                    .frame(width: s * 0.15, height: s * 0.08)
            case .neutral:
                Capsule()
                    .fill(Theme.onPastel)
                    .frame(width: s * 0.09, height: s * 0.028)
            case .sad:
                CurveShape(bend: -1)
                    .stroke(Theme.onPastel, style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                    .frame(width: s * 0.11, height: s * 0.06)
            }
        }
        .offset(y: s * 0.08)
    }

    private var tear: some View {
        Circle()
            .fill(Theme.sky)
            .frame(width: s * 0.05, height: s * 0.05)
            .offset(x: s * 0.13, y: s * 0.07)
    }

    // MARK: - Milestone decorations
    private var leaf: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: s * 0.2))
            .foregroundStyle(Theme.teal)
            .rotationEffect(.degrees(-38))
            .offset(x: -s * 0.3, y: -s * 0.47)
            .accessibilityHidden(true)
    }

    private var scarf: some View {
        ZStack {
            Capsule()
                .fill(Theme.coral)
                .frame(width: s * 0.5, height: s * 0.09)
            RoundedRectangle(cornerRadius: s * 0.025, style: .continuous)
                .fill(Theme.coral)
                .frame(width: s * 0.08, height: s * 0.15)
                .rotationEffect(.degrees(-12))
                .offset(x: s * 0.17, y: s * 0.08)
        }
        .offset(y: s * 0.4)
    }

    private var sparkles: some View {
        ZStack {
            sparkle(size: 0.17, x: -0.47, y: -0.17, delay: 0)
            sparkle(size: 0.12, x: 0.47, y: -0.25, delay: 0.5)
            sparkle(size: 0.1, x: 0.43, y: 0.2, delay: 1)
        }
    }

    private func sparkle(size: CGFloat, x: CGFloat, y: CGFloat, delay: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: s * size))
            .foregroundStyle(Theme.yellow)
            .scaleEffect(twinkling ? 1 : 0.7)
            .opacity(twinkling ? 1 : 0.55)
            .animation(canAnimate ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(delay) : nil, value: twinkling)
            .offset(x: s * x, y: s * y)
            .accessibilityHidden(true)
    }

    private var partyHat: some View {
        ZStack(alignment: .top) {
            HatShape()
                .fill(Theme.indigo)
                .frame(width: s * 0.26, height: s * 0.3)
            Circle()
                .fill(Theme.yellow)
                .frame(width: s * 0.075, height: s * 0.075)
                .offset(y: -s * 0.03)
        }
        .rotationEffect(.degrees(10))
        .offset(x: s * 0.06, y: -s * 0.53)
    }

    // MARK: - Animation
    private func startBreathing() async {
        breathing = false
        twinkling = false
        guard canAnimate else { return }
        try? await Task.sleep(for: .milliseconds(30))
        withAnimation(.easeInOut(duration: mood == .excited ? 0.45 : 2.4).repeatForever(autoreverses: true)) {
            breathing = true
        }
        twinkling = true
    }

    private func blinkLoop() async {
        blinking = false
        guard canAnimate else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5)))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.08)) { blinking = true }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.easeInOut(duration: 0.1)) { blinking = false }
        }
    }
}

// MARK: - Shapes
/// A quadratic curve across the rect. `bend` > 0 dips down (smile), < 0 arches up (frown / "^" eye).
private struct CurveShape: Shape {
    var bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY + bend * rect.height)
        )
        return path
    }
}

private struct OpenMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 2)
        )
        path.closeSubpath()
        return path
    }
}

private struct HatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Mood helpers
extension PetState.MoodExpression {
    var label: String {
        switch self {
        case .happy:   "Happy"
        case .sad:     "Sad"
        case .neutral: "Okay"
        case .excited: "Excited"
        }
    }
}

#Preview("Moods") {
    HStack(spacing: 16) {
        MochiView(mood: .happy, size: 90)
        MochiView(mood: .excited, size: 90)
        MochiView(mood: .neutral, size: 90)
        MochiView(mood: .sad, size: 90)
    }
    .padding(40)
}

#Preview("Milestones") {
    HStack(spacing: 24) {
        ForEach(GoalMilestone.allCases, id: \.self) { band in
            MochiView(mood: .happy, milestone: band, size: 80)
        }
    }
    .padding(50)
}
