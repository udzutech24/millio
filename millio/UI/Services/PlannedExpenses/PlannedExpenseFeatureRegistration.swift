//
//  PlannedExpenseFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Регистрация фичи планируемых расходов для backup/restore
enum PlannedExpenseFeatureRegistration {
    static func register() {
        ModelTypeRegistry.shared.register(PlannedExpense.self, typeName: "PlannedExpense")
        ModelTypeRegistry.shared.registerImporter(PlannedExpenseImporter.self)
    }
}

// MARK: - Planned Expense Importer

struct PlannedExpenseImporter: ModelImporter {
    static func importType() -> String {
        "PlannedExpense"
    }
    
    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let name = dict["name"] as? String,
              let amount = dict["amount"] as? Double,
              let currency = dict["currency"] as? String,
              let plannedDateTimestamp = dict["plannedDate"] as? TimeInterval,
              let categoryRaw = dict["categoryRaw"] as? String,
              let priorityRaw = dict["priorityRaw"] as? String,
              let createdAtTimestamp = dict["createdAt"] as? TimeInterval,
              let updatedAtTimestamp = dict["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        let plannedDate = Date(timeIntervalSince1970: plannedDateTimestamp)
        let createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
        let updatedAt = Date(timeIntervalSince1970: updatedAtTimestamp)
        
        let category = PlannedExpenseCategory(rawValue: categoryRaw) ?? .other
        let priority = PlannedExpensePriority(rawValue: priorityRaw) ?? .normal
        let isFavorite = dict["isFavorite"] as? Bool ?? false
        let isPaid = dict["isPaid"] as? Bool ?? false
        
        // Проверяем, не существует ли уже такой расход
        let uniqueID = dict["plannedExpenseUniqueID"] as? String
        if let uniqueID = uniqueID {
            let descriptor = FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { expense in
                    expense.plannedExpenseUniqueID == uniqueID
                }
            )
            if let existing = try? context.fetch(descriptor).first {
                // Обновляем существующий
                existing.name = name
                existing.amount = amount
                existing.currency = currency
                existing.plannedDate = plannedDate
                existing.categoryRaw = categoryRaw
                existing.priorityRaw = priorityRaw
                existing.isFavorite = isFavorite
                existing.isPaid = isPaid
                existing.updatedAt = updatedAt
                return
            }
        }
        
        // Создаем новый расход
        let expense = PlannedExpense(
            name: name,
            amount: amount,
            currency: currency,
            plannedDate: plannedDate,
            category: category,
            priority: priority,
            isFavorite: isFavorite,
            isPaid: isPaid
        )
        expense.createdAt = createdAt
        expense.updatedAt = updatedAt
        
        context.insert(expense)
    }
}
