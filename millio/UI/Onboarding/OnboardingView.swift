//
//  OnboardingView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @Bindable var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 32) {
            Text("welcome")
                .font(.largeTitle)
                .bold()
            
            Text("Это ядро приложения с поддержкой резервного копирования")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Button("start") {
                completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
    
    private func completeOnboarding() {
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
