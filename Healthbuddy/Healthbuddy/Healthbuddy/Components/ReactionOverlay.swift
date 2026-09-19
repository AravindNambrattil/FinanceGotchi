import SwiftUI

struct ReactionOverlay: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            MochiView(mood: .excited, size: 84)

            Text(message)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onDismiss) {
                Text("Got it!")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MellowFilledButtonStyle())
            .padding(.horizontal, 32)
        }
        .padding(32)
        .mellowCard(Theme.surface, radius: 32)
        .padding(.horizontal, 24)
        .shadow(radius: 20)
        .transition(.scale.combined(with: .opacity))
    }
}

/// Wraps a view and overlays a reaction message when `message` is non-nil.
struct ReactionOverlayModifier: ViewModifier {
    let message: String?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: message != nil ? 2 : 0)
                .animation(.easeInOut(duration: 0.2), value: message != nil)

            if let message {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ReactionOverlay(message: message, onDismiss: onDismiss)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: message != nil)
    }
}

extension View {
    func reactionOverlay(message: String?, onDismiss: @escaping () -> Void) -> some View {
        modifier(ReactionOverlayModifier(message: message, onDismiss: onDismiss))
    }
}
