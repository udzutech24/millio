//
//  InvestmentFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Investment для backup/restore
struct InvestmentFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Investment.self, typeName: "Investment")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(InvestmentImporter.self)
    }
}

// MARK: - Investment Importer

struct InvestmentImporter: ModelImporter {
    static func importType() -> String {
        "Investment"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let investmentTypeRaw = data["investmentTypeRaw"] as? String,
              let categoryRaw = data["categoryRaw"] as? String,
              let amount = data["amount"] as? Double,
              let currency = data["currency"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Получаем priority (для обратной совместимости используем normal по умолчанию)
        let priorityRaw = data["priorityRaw"] as? String ?? "normal"
        let priority = InvestmentPriority(rawValue: priorityRaw) ?? .normal
        
        // Получаем includeInTotal (для обратной совместимости используем true по умолчанию)
        let includeInTotal = data["includeInTotal"] as? Bool ?? true
        let initialAmount = data["initialAmount"] as? Double
        let hasInitialAmount = data["hasInitialAmount"] as? Bool
        
        // Проверяем, не существует ли уже инвестиция с такими же данными
        let existingInvestmentDescriptor = FetchDescriptor<Investment>(
            predicate: #Predicate<Investment> { investment in
                investment.name == name &&
                investment.investmentTypeRaw == investmentTypeRaw &&
                investment.categoryRaw == categoryRaw &&
                investment.amount == amount &&
                investment.currency == currency
            }
        )
        
        // Если инвестиция уже существует, обновляем ее данные вместо создания новой
        if let existingInvestment = try? context.fetch(existingInvestmentDescriptor).first {
            if let uniqueID = data["investmentUniqueID"] as? String, !uniqueID.isEmpty {
                existingInvestment.uniqueID = uniqueID
            }
            if let initialAmount = initialAmount {
                existingInvestment.initialAmount = initialAmount
                existingInvestment.hasInitialAmount = hasInitialAmount ?? true
            }
            existingInvestment.isFavorite = data["isFavorite"] as? Bool ?? false
            existingInvestment.priority = priority
            existingInvestment.includeInTotal = includeInTotal
            existingInvestment.updatedAt = Date(timeIntervalSince1970: updatedAt)
            existingInvestment.ensureUniqueID()
            
            AppLogger.log(.info, category: "InvestmentImporter", "Updated existing investment '\(name)' instead of creating duplicate")
            return
        }
        
        // Создаем новую инвестицию только если она не существует
        let investment = Investment(
            name: name,
            investmentType: InvestmentType(rawValue: investmentTypeRaw) ?? .positive,
            category: InvestmentCategory(rawValue: categoryRaw) ?? .other,
            amount: amount,
            currency: currency,
            includeInTotal: includeInTotal,
            priority: priority,
            isFavorite: data["isFavorite"] as? Bool ?? false
        )
        
        investment.createdAt = Date(timeIntervalSince1970: createdAt)
        investment.updatedAt = Date(timeIntervalSince1970: updatedAt)
        if let initialAmount = initialAmount {
            investment.initialAmount = initialAmount
            investment.hasInitialAmount = hasInitialAmount ?? true
        } else {
            investment.initialAmount = amount
            investment.hasInitialAmount = true
        }
        if let uniqueID = data["investmentUniqueID"] as? String, !uniqueID.isEmpty {
            investment.uniqueID = uniqueID
        }
        investment.ensureUniqueID()
        
        context.insert(investment)
    }
}
