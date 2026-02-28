//
//  AppSchema.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Схема SwiftData для приложения
/// Собирает все типы моделей из ядра и зарегистрированных фич
struct AppSchema {
    /// Создает схему, включая базовые типы ядра и зарегистрированные типы из ModelTypeRegistry
    static func create() -> Schema {
        var modelTypes: [any PersistentModel.Type] = []
        
        // Базовые типы ядра
        modelTypes.append(Item.self)
        
        // Типы из ModelTypeRegistry
        let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
        for (_, type) in registeredTypes {
            // Все Persistable типы должны быть PersistentModel
            // Приводим напрямую без conditional cast
            let persistentType = type as any PersistentModel.Type
            // Проверяем, что тип еще не добавлен
            if !modelTypes.contains(where: { $0 == persistentType }) {
                modelTypes.append(persistentType)
            }
        }
        
        return Schema(modelTypes)
    }
}
