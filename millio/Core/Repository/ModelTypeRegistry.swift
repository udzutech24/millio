//
//  ModelTypeRegistry.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Регистрация типов моделей для экспорта/импорта
/// Позволяет фичам регистрировать свои типы без изменения ядра
protocol ModelTypeRegistryProtocol {
    func register<T: Persistable>(_ type: T.Type, typeName: String)
    func getExportableTypes() -> [String: any Persistable.Type]
}

final class ModelTypeRegistry: ModelTypeRegistryProtocol {
    static let shared = ModelTypeRegistry()
    
    private var registeredTypes: [String: any Persistable.Type] = [:]
    private let queue = DispatchQueue(label: "com.millio.modelTypeRegistry", attributes: .concurrent)
    
    private init() {
        // Регистрируем базовые типы ядра
        register(Item.self, typeName: "Item")
    }
    
    func register<T: Persistable>(_ type: T.Type, typeName: String) {
        queue.async(flags: .barrier) {
            self.registeredTypes[typeName] = type
        }
    }
    
    func getExportableTypes() -> [String: any Persistable.Type] {
        queue.sync {
            return registeredTypes
        }
    }
}
