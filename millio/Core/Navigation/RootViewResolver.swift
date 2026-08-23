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
    case autoRestoring
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
        if lifecycle == .launching {
            return .launching
        }

        if !isAuthenticated && !isGuestModeEnabled {
            // Пока сессия восстанавливается, мы ещё не знаем, залогинен ли пользователь —
            // показываем сплэш вместо мигания экраном авторизации.
            return authStatus == .restoring ? .launching : .auth
        }

        // authStatus == .restoring НЕ откатывает уже разрешённый маршрут назад в .launching.
        // Иначе холодный старт авторизованного пользователя мигал: cold start поднимает сессию
        // из локального снапшота (.authenticated) и выставляет lifecycle = .ready → монтируется
        // RootTabView, следом фоновой задачей стартует сетевой restoreSession (status = .restoring)
        // → дерево сносилось в LaunchingView и монтировалось заново («открыл — закрыл — открыл»).

        switch lifecycle {
        case .launching:
            return .launching
        case .onboarding:
            return .onboarding
        case .restoring:
            return .restoring
        case .autoRestoring:
            return .autoRestoring
        case .ready:
            return .ready
        case .error:
            return .error
        }
    }

    static func shouldResetNavigationPath(from oldRoute: RootViewRoute, to newRoute: RootViewRoute) -> Bool {
        oldRoute != newRoute
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
            case .autoRestoring:
                AutoRestoringView(backupDate: appState.lastBackupDate)
            case .ready:
                RootTabView(router: router)
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
        .onChange(of: route) { oldRoute, newRoute in
            guard Self.shouldResetNavigationPath(from: oldRoute, to: newRoute) else { return }
            router.popToRoot()
        }
        .onChange(of: authManager.isAuthenticated) { wasAuthenticated, isAuthenticated in
            guard !wasAuthenticated, isAuthenticated else { return }
            router.popToRoot()
        }
        .environment(router)
    }
}
