//
//  MainAppViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import Combine

/// Состояние главного экрана
struct MainAppState {
    // Пока пустое, можно добавить состояние по мере необходимости
}

/// ViewModel для главного экрана
@MainActor
final class MainAppViewModel: ViewModelProtocol {
    @Published var state = MainAppState()
    
    private let router: AppRouter
    
    init(router: AppRouter) {
        self.router = router
    }
    
    enum Action {
        case navigateToService(AppRoute)
        case navigateToProfile
        case navigateToSubscription
    }
    
    func handle(_ action: Action) {
        switch action {
        case .navigateToService(let route):
            router.push(route)
        case .navigateToProfile:
            router.push(.profile)
        case .navigateToSubscription:
            router.push(.subscription)
        }
    }
}
