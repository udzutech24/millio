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
        
        
        // Явно добавляем модели Card
        if !modelTypes.contains(where: { $0 == Card.self }) {
            modelTypes.append(Card.self)
        }
        
        // Явно добавляем модели Cashback
        if !modelTypes.contains(where: { $0 == Cashback.self }) {
            modelTypes.append(Cashback.self)
        }
        
        // Явно добавляем модели Credit
        if !modelTypes.contains(where: { $0 == Credit.self }) {
            modelTypes.append(Credit.self)
        }
        
        // Явно добавляем модели Habit
        if !modelTypes.contains(where: { $0 == Habit.self }) {
            modelTypes.append(Habit.self)
        }
        
        // Явно добавляем модели HabitEntry
        if !modelTypes.contains(where: { $0 == HabitEntry.self }) {
            modelTypes.append(HabitEntry.self)
        }
        
        // Явно добавляем модели Debt
        if !modelTypes.contains(where: { $0 == Debt.self }) {
            modelTypes.append(Debt.self)
        }
        
        // Явно добавляем модели Investment
        if !modelTypes.contains(where: { $0 == Investment.self }) {
            modelTypes.append(Investment.self)
        }
        
        // Явно добавляем модели PlannedExpense
        if !modelTypes.contains(where: { $0 == PlannedExpense.self }) {
            modelTypes.append(PlannedExpense.self)
        }
        
        // Явно добавляем модели FinanceGroup
        if !modelTypes.contains(where: { $0 == FinanceGroup.self }) {
            modelTypes.append(FinanceGroup.self)
        }
        
        // Явно добавляем модели FinanceAccount
        if !modelTypes.contains(where: { $0 == FinanceAccount.self }) {
            modelTypes.append(FinanceAccount.self)
        }
        
        return Schema(modelTypes)
    }
}
