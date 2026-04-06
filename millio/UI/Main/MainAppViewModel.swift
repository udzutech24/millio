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
    var layoutMode: MainScreenLayoutMode
}

/// ViewModel для главного экрана
@MainActor
final class MainAppViewModel: ViewModelProtocol {
    @Published var state: MainAppState
    
    private let router: AppRouter
    
    init(router: AppRouter) {
        self.router = router
        self.state = MainAppState(layoutMode: SettingsManager.shared.mainScreenLayoutMode)
    }
    
    enum Action {
        case navigateToService(AppRoute)
        case navigateToProfile
        case navigateToSubscription
        case setLayoutMode(MainScreenLayoutMode)
    }
    
    func handle(_ action: Action) {
        switch action {
        case .navigateToService(let route):
            router.push(route)
        case .navigateToProfile:
            router.push(.profile)
        case .navigateToSubscription:
            router.push(.subscription)
        case .setLayoutMode(let mode):
            guard state.layoutMode != mode else { return }
            state.layoutMode = mode
            SettingsManager.shared.mainScreenLayoutMode = mode
        }
    }
}
