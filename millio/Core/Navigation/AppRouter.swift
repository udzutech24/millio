//
//  AppRouter.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

enum AppRoute: Hashable {
    case onboarding
    case restore
    case main
    case error(AppError)
    
    // Service screens
    case finances
    case courses
    case cashback
    case cashflow
    
    // Other screens
    case profile
    case subscription
    case userSubscriptions
}

@Observable
@MainActor
final class AppRouter {
    var currentRoute: AppRoute = .onboarding
    var navigationPath = NavigationPath()
    var selectedTab: RootTab = .dashboard
    var pendingFABAction: FABAction? = nil
    var showingSubscription = false

    func navigate(to route: AppRoute) {
        currentRoute = route
        popToRoot()
    }

    func push(_ route: AppRoute) {
        switch route {
        case .subscription:
            showingSubscription = true
        default:
            navigationPath.append(route)
        }
    }

    /// Clears pushed screens and returns to the current root container.
    func popToRoot() {
        navigationPath = NavigationPath()
    }
}
