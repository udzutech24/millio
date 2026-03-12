import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @Bindable var router: AppRouter
    @State private var showsStartScreen = true

    var body: some View {
        Group {
            if showsStartScreen {
                OnboardingStartView(
                    locale: appState.selectedLanguage.locale ?? Locale.current,
                    onStart: openQuickSetup,
                    onSkip: skipOnboarding
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                QuickSetupView(
                    appState: appState,
                    mode: .onboarding,
                    onCompleted: completeOnboarding,
                    onSkipped: skipOnboarding
                )
            }
        }
    }

    private func openQuickSetup() {
        withAnimation(.easeInOut(duration: 0.24)) {
            showsStartScreen = false
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        appState.lifecycle = .ready
    }

    private func skipOnboarding() {
        SettingsManager.shared.isQuickSetupCompleted = false
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        appState.lifecycle = .ready
    }
}

#Preview {
    OnboardingView(
        appState: AppState(),
        router: AppRouter()
    )
}
