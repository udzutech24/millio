//
//  FeatureRegistry.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Протокол для регистрации feature модулей
protocol FeatureModule {
    /// Регистрация моделей в ModelTypeRegistry
    func registerModels(in registry: ModelTypeRegistryProtocol)
    
    /// Регистрация routes в AppRouter (опционально)
    func registerRoutes(in router: AppRouter)
    
    /// Конфигурация зависимостей (опционально)
    func configureDependencies(in container: DIContainer)
}

/// Реестр feature модулей
final class FeatureRegistry {
    static let shared = FeatureRegistry()
    
    private var features: [FeatureModule] = []
    private let queue = DispatchQueue(label: "com.millio.featureRegistry", attributes: .concurrent)
    
    private init() {}
    
    /// Зарегистрировать feature модуль
    func register(_ feature: FeatureModule) {
        queue.sync(flags: .barrier) {
            self.features.append(feature)
        }
    }
    
    /// Настроить все зарегистрированные модули
    func configureAll() {
        queue.sync {
            for feature in features {
                feature.registerModels(in: ModelTypeRegistry.shared)
                // Routes и dependencies можно настроить позже при необходимости
            }
        }
    }
    
    struct State {
        let features: [FeatureModule]
    }
    
    func captureState() -> State {
        queue.sync { State(features: features) }
    }
    
    func restoreState(_ state: State) {
        queue.sync(flags: .barrier) {
            features = state.features
        }
    }
}
