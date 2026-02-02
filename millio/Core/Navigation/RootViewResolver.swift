//
//  RootViewResolver.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

enum RootViewRoute: Equatable {
    case launching
    case onboarding
    case restoring
    case ready
    case error
}

struct RootViewResolver: View {
    @Bindable var appState: AppState
    @State private var router = AppRouter()
    
    static func route(for lifecycle: AppLifecycleState) -> RootViewRoute {
        switch lifecycle {
        case .launching:
            return .launching
        case .onboarding:
            return .onboarding
        case .restoring:
            return .restoring
        case .ready:
            return .ready
        case .error:
            return .error
        }
    }
    
    var body: some View {
        Group {
            switch Self.route(for: appState.lifecycle) {
            case .launching:
                LaunchingView()
            case .onboarding:
                OnboardingView(appState: appState, router: router)
            case .restoring:
                RestoreView(appState: appState, router: router)
            case .ready:
                MainAppView(router: router)
            case .error:
                if case .error(let error) = appState.lifecycle {
                    ErrorView(error: error, appState: appState, router: router)
                } else {
                    EmptyView()
                }
            }
        }
        .environment(router)
    }
}
