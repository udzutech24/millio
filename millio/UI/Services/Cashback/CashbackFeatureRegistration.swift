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
        ModelTypeRegistry.shared.registerBackupExporter("Cashback") { context in
            let cashbackDescriptor = FetchDescriptor<Cashback>()
            let cashbacks = try context.fetch(cashbackDescriptor)
            
            let cardDescriptor = FetchDescriptor<Card>()
            let cards = try context.fetch(cardDescriptor)
            var cardIDMapping: [String: String] = [:]
            for card in cards {
                cardIDMapping[String(describing: card.persistentModelID)] = card.cardUniqueID
            }
            
            var exported: [[String: Any]] = []
            exported.reserveCapacity(cashbacks.count)
            
            for cashback in cashbacks {
                let data = try cashback.export()
                guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                
                if let cardIDs = json["cardIDs"] as? [String] {
                    let converted = cardIDs.map { cardIDMapping[$0] ?? $0 }
                    json["cardIDs"] = converted
                    if converted != cardIDs {
                        json["_cardIDs_legacy"] = cardIDs
                    }
                }
                
                json["_type"] = "Cashback"
                exported.append(json)
            }
            
            return exported
        }
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(CashbackImporter.self)
    }
}

// MARK: - Cashback Importer

struct CashbackImporter: ModelImporter {
    static func importType() -> String {
        "Cashback"
    }
    
    static var importPriority: Int { 20 }
    
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
        
        let cardDescriptor = FetchDescriptor<Card>()
        let cards = (try? context.fetch(cardDescriptor)) ?? []
        var cardUniqueIDToPersistentID: [String: String] = [:]
        for card in cards {
            cardUniqueIDToPersistentID[card.cardUniqueID] = String(describing: card.persistentModelID)
        }
        
        let resolvedCardIDs = cardIDs.map { cardUniqueIDToPersistentID[$0] ?? $0 }
        
        let cashback = Cashback(
            name: name,
            category: CashbackCategory(rawValue: categoryRaw) ?? .other,
            percentage: percentage,
            cardIDs: resolvedCardIDs
        )
        
        // Восстанавливаем даты
        cashback.createdAt = Date(timeIntervalSince1970: createdAt)
        cashback.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
        context.insert(cashback)
    }
}
