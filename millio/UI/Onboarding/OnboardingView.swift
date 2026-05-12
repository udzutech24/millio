import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @Bindable var router: AppRouter

    var body: some View {
        QuickSetupView(
            appState: appState,
            mode: .onboarding,
            onCompleted: completeOnboarding,
            onSkipped: skipOnboarding
        )
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        appState.lifecycle = .ready
        appState.refreshLanguageToken()
    }

    private func skipOnboarding() {
        SettingsManager.shared.isQuickSetupCompleted = false
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        appState.lifecycle = .ready
        appState.refreshLanguageToken()
    }
}

#Preview {
    OnboardingView(
        appState: AppState(),
        router: AppRouter()
    )
}
