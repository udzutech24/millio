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
    case credits
    case habits
    case cardIndex
    case debts
    case investments
    case plannedExpenses
    
    // Other screens
    case profile
    case subscription
}

@Observable
final class AppRouter {
    var currentRoute: AppRoute = .onboarding
    var navigationPath = NavigationPath()
    
    func navigate(to route: AppRoute) {
        currentRoute = route
        navigationPath = NavigationPath()
    }
    
    func push(_ route: AppRoute) {
        navigationPath.append(route)
    }
}
