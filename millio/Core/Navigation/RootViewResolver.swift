//
//  RootViewResolver.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

enum RootViewRoute: Equatable {
    case launching
    case auth
    case onboarding
    case restoring
    case ready
    case error
}

struct RootViewResolver: View {
    @Bindable var appState: AppState
    @Environment(AuthManager.self) private var authManager
    @State private var router = AppRouter()
    
    static func route(
        for lifecycle: AppLifecycleState,
        authStatus: AuthManagerStatus,
        isAuthenticated: Bool,
        isGuestModeEnabled: Bool
    ) -> RootViewRoute {
        if lifecycle == .launching || authStatus == .restoring {
            return .launching
        }

        if !isAuthenticated && !isGuestModeEnabled {
            return .auth
        }

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
        let route = Self.route(
            for: appState.lifecycle,
            authStatus: authManager.status,
            isAuthenticated: authManager.isAuthenticated,
            isGuestModeEnabled: appState.isGuestModeEnabled
        )

        return Group {
            switch route {
            case .launching:
                LaunchingView()
            case .auth:
                AuthWelcomeView()
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
        .task {
            authManager.logResolvedRoute(route)
        }
        .onChange(of: route) { _, newRoute in
            authManager.logResolvedRoute(newRoute)
        }
        .onChange(of: authManager.isAuthenticated) { wasAuthenticated, isAuthenticated in
            guard !wasAuthenticated, isAuthenticated else { return }
            router.popToRoot()
        }
        .environment(router)
    }
}
