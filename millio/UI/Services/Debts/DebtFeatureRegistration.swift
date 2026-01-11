//
//  DebtFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Debt для backup/restore
struct DebtFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Debt.self, typeName: "Debt")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(DebtImporter.self)
    }
}

// MARK: - Debt Importer

struct DebtImporter: ModelImporter {
    static func importType() -> String {
        "Debt"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let debtTypeRaw = data["debtTypeRaw"] as? String,
              let amount = data["amount"] as? Double,
              let currency = data["currency"] as? String,
              let contactName = data["contactName"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Получаем priority (для обратной совместимости используем normal по умолчанию)
        let priorityRaw = data["priorityRaw"] as? String ?? "normal"
        let priority = DebtPriority(rawValue: priorityRaw) ?? .normal
        
        let isPaid = data["isPaid"] as? Bool ?? false
        
        // Проверяем, не существует ли уже долг с такими же данными
        let existingDebtDescriptor = FetchDescriptor<Debt>(
            predicate: #Predicate<Debt> { debt in
                debt.name == name &&
                debt.debtTypeRaw == debtTypeRaw &&
                debt.amount == amount &&
                debt.currency == currency &&
                debt.contactName == contactName
            }
        )
        
        // Если долг уже существует, обновляем его данные вместо создания новой
        if let existingDebt = try? context.fetch(existingDebtDescriptor).first {
            existingDebt.isFavorite = data["isFavorite"] as? Bool ?? false
            existingDebt.isPaid = isPaid
            existingDebt.priority = priority
            if let dueDate = data["dueDate"] as? TimeInterval {
                existingDebt.dueDate = Date(timeIntervalSince1970: dueDate)
            } else {
                existingDebt.dueDate = nil
            }
            existingDebt.updatedAt = Date(timeIntervalSince1970: updatedAt)
            
            AppLogger.log(.info, category: "DebtImporter", "Updated existing debt '\(name)' instead of creating duplicate")
            return
        }
        
        // Создаем новый долг только если он не существует
        let debt = Debt(
            name: name,
            debtType: DebtType(rawValue: debtTypeRaw) ?? .iOwe,
            amount: amount,
            currency: currency,
            contactName: contactName,
            dueDate: (data["dueDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            priority: priority,
            isFavorite: data["isFavorite"] as? Bool ?? false,
            isPaid: isPaid
        )
        
        debt.createdAt = Date(timeIntervalSince1970: createdAt)
        debt.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
        context.insert(debt)
    }
}
