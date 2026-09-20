import SwiftUI

/// One-shot confetti burst drawn from SwiftUI shapes. Renders nothing under Reduce Motion.
struct ConfettiView: View {
    private struct Piece {
        let x: CGFloat        // 0...1 across the width
        let delay: Double
        let fall: Double      // seconds to cross the screen
        let size: CGFloat
        let color: Color
        let spin: Double
        let sway: CGFloat
        let isRound: Bool

        static func random() -> Piece {
            Piece(
                x: .random(in: 0...1),
                delay: .random(in: 0...0.9),
                fall: .random(in: 1.8...3.0),
                size: .random(in: 7...12),
                color: [Theme.yellow, Theme.coral, Theme.teal, Theme.indigo, Theme.pink, Theme.sage].randomElement() ?? Theme.yellow,
                spin: .random(in: -2...2),
                sway: .random(in: 8...26),
                isRound: Bool.random()
            )
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var pieces: [Piece] = (0..<46).map { _ in Piece.random() }

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start)
                GeometryReader { geo in
                    ForEach(pieces.indices, id: \.self) { i in
                        let piece = pieces[i]
                        let progress = (t - piece.delay) / piece.fall
                        if progress > 0 && progress < 1 {
                            Group {
                                if piece.isRound {
                                    Circle().fill(piece.color)
                                } else {
                                    RoundedRectangle(cornerRadius: 2).fill(piece.color)
                                }
                            }
                            .frame(width: piece.size, height: piece.size * (piece.isRound ? 1 : 0.55))
                            .rotationEffect(.degrees(progress * piece.spin * 360))
                            .position(
                                x: geo.size.width * piece.x + CGFloat(sin(progress * 7 + piece.spin)) * piece.sway,
                                y: -20 + (geo.size.height + 40) * progress
                            )
                            .opacity(1 - max(0, (progress - 0.8) * 5))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
