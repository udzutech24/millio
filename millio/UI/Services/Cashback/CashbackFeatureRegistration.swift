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
            
            var exported: [[String: Any]] = []
            exported.reserveCapacity(cashbacks.count)
            
            for cashback in cashbacks {
                let data = try cashback.export()
                var json = try BackupJSON.decodeExportedDict(data, typeName: "Cashback")
                
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
              let cardIDs = data["cardIDs"] as? [String],
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        let cardDescriptor = FetchDescriptor<Card>()
        let cards = (try? context.fetch(cardDescriptor)) ?? []
        let validUniqueIDs = Set(cards.map(\.cardUniqueID))
        guard cardIDs.allSatisfy({ validUniqueIDs.contains($0) }) else {
            throw AppError.backupCorrupted
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
