//
//  CashbackFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Cashback для backup/restore
struct CashbackFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Cashback.self, typeName: "Cashback")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(CashbackImporter.self)
    }
}

// MARK: - Cashback Importer

struct CashbackImporter: ModelImporter {
    static func importType() -> String {
        "Cashback"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let categoryRaw = data["categoryRaw"] as? String,
              let percentage = data["percentage"] as? Double,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Поддержка обратной совместимости: если есть cardID (старый формат), конвертируем в массив
        var cardIDs: [String] = []
        if let cardIDsArray = data["cardIDs"] as? [String] {
            cardIDs = cardIDsArray
        } else if let cardID = data["cardID"] as? String {
            // Обратная совместимость: старый формат с одной картой
            cardIDs = [cardID]
        }
        
        let cashback = Cashback(
            name: name,
            category: CashbackCategory(rawValue: categoryRaw) ?? .other,
            percentage: percentage,
            cardIDs: cardIDs
        )
        
        // Восстанавливаем даты
        cashback.createdAt = Date(timeIntervalSince1970: createdAt)
        cashback.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
        context.insert(cashback)
    }
}
