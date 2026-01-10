//
//  RootViewResolver.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct RootViewResolver: View {
    @Bindable var appState: AppState
    @State private var router = AppRouter()
    
    var body: some View {
        Group {
            switch appState.lifecycle {
            case .launching:
                LaunchingView()
            case .onboarding:
                OnboardingView(appState: appState, router: router)
            case .restoring:
                RestoreView(appState: appState, router: router)
            case .ready:
                MainAppView(router: router)
            case .error(let error):
                ErrorView(error: error, appState: appState, router: router)
            }
        }
        .environment(router)
    }
}
