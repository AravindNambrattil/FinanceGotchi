import SwiftUI

/// Decides which screen to show: intro (landing + onboarding), sign-in, or the app.
struct RootView: View {
    @State private var session = SessionStore()

    var body: some View {
        ZStack {
            if !session.hasOnboarded {
                WelcomeFlow(session: session)
                    .transition(.opacity)
            } else if !session.isSignedIn {
                LoginView(session: session)
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .environment(session)
        .animation(.easeInOut(duration: 0.3), value: session.hasOnboarded)
        .animation(.easeInOut(duration: 0.3), value: session.isSignedIn)
        .background(Theme.background)
    }
}

#Preview {
    RootView()
}
